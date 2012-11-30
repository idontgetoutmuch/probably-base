-- Pure Haskell implementation of standard BFGS algorithm with cubic
-- line search, with the BFGS step exposed to provide access to
-- intermediate Hessian estimates.

module Math.Probably.BFGS 
       ( BFGSOpts (..)
       , LineSearchOpts (..)
       , BFGS (..)
       , bfgs, bfgsWith
       , bfgsInit
       , bfgsStep, bfgsStepWith )
where

import Numeric.LinearAlgebra
import Numeric.LinearAlgebra.Util
import Data.Default

import Debug.Trace

-- Type synonyms mostly just for documentation purposes...
type Point = Vector Double
type Gradient = Vector Double
type Direction = Vector Double
type Fn = Point -> Double
type GradFn = Point -> Vector Double
type Hessian = Matrix Double

--------------------------------------------------------------------------------
--
--  BFGS
--

-- Options for BFGS solver: point tolerance, gradient tolerance,
-- maximum iterations.
--
data BFGSOpts = BFGSOpts { ptol :: Double
                         , gtol :: Double
                         , maxiters :: Int } deriving Show

instance Default BFGSOpts where
  def = BFGSOpts 1.0E-7 1.0E-7 200


-- BFGS solver data to carry between steps: current point, function
-- value at point, gradient at point, current direction, current
-- Hessian estimate, maximum line search step.
--
data BFGS = BFGS { p :: Point
                 , fp :: Double
                 , g :: Gradient
                 , xi :: Direction
                 , h :: Matrix Double 
                 , stpmax :: Double } deriving Show


-- Main solver interface with default options.
--
bfgs :: Fn -> GradFn -> Point -> Either String (Point, Hessian)
bfgs = bfgsWith def


{- Collection solver state into an infinite list: useful as "take n $
-- bfgsCollect f df b0"
--
bfgsCollect :: Fn -> GradFn -> BFGS -> [BFGS]
bfgsCollect f df b0 = map snd $ iterate step (False,b0)
  where step (cvg,b) = if cvg then b else bfgsStep f df b

-}
-- Utility function to set up initial BFGS state for bfgsCollect.
--
bfgsInit :: Fn -> GradFn -> Point -> BFGS
bfgsInit f df p0 = BFGS p0 (f p0) g0 (-g0) (ident n) (maxStep p0)
  where n = dim p0
        g0 = df p0


-- Main iteration routine: sets up initial BFGS state, then steps
-- until converged or maximum iterations exceeded.
--
bfgsWith :: BFGSOpts -> Fn -> GradFn -> Point -> Either String (Point, Hessian)
bfgsWith opt@(BFGSOpts _ _ maxiters) f df p0 = go 0 b0
  where go iters b = 
          if iters > maxiters
          then Left "maximum iterations exceeded in bfgs"
          else case bfgsStepWith opt f df b of
            (True, b') -> Right (p b', h b')
            (False, b') -> trace (show $ p b') $ go (iters+1) b'
        g0 = df p0
        b0 = BFGS p0 (f p0) g0 (-g0) (ident $ dim p0) (maxStep p0)


-- Do a BFGS step with default parameters.
--
bfgsStep :: Fn -> GradFn -> BFGS -> (Bool, BFGS)
bfgsStep = bfgsStepWith def


-- Main BFGS step routine.  This is a more or less verbatim
-- translation of the description in Section 10.7 of Numerical Recipes
-- in C, 2nd ed.
--
bfgsStepWith :: BFGSOpts -> Fn -> GradFn -> BFGS -> (Bool, BFGS)
bfgsStepWith (BFGSOpts ptol gtol _) f df (BFGS p fp g xi h stpmax) = 
  (cvg, BFGS pn fpn gn xin hn stpmax)
  where (pn, fpn) = lineSearch f p fp g xi stpmax
        gn = df pn ; dp = pn - p ; dg = gn - g
        hdg = h <> dg
        dpdg = dp `dot` dg ; dghdg = dg `dot` hdg
        u = (1/dpdg) `scale` dp - (1/dghdg) `scale` hdg
        o2 v = v `outer` v
        hn = h + (1/dpdg) `scale` o2 dp - (1/dghdg) `scale` o2 hdg + 
             dghdg `scale` o2 u
        xin = -hn <> gn
        cvg = maxabsratio xi p < ptol || maxabsratio' (fpn `max` 1) gn p < gtol


--------------------------------------------------------------------------------
--
--  LINE SEARCH
--

-- Options for line search routine: point tolerance, "acceptable
-- decrease" parameter.
--
data LineSearchOpts = LineSearchOpts { xtol :: Double
                                     , alpha :: Double } deriving Show

instance Default LineSearchOpts where
  def = LineSearchOpts 1.0E-7 1.0E-4


-- Maximum line search step length.
--
maxStep :: Point -> Double
maxStep p0 = (100 * (norm p0 `max` n))
  where n = fromIntegral (dim p0)


-- Line search with default parameters.
--
lineSearch :: Fn -> Point -> Double -> Gradient -> Direction -> 
              Double -> (Point, Double)
lineSearch = lineSearchWith def


-- Main line search routine.  This is kind of nasty to translate into
-- functional form because of the switching about between the
-- quadratic and cubic approximations.  It works, but it could be
-- prettier.
--
lineSearchWith :: LineSearchOpts -> Fn -> Point -> Double -> Gradient -> 
                  Direction -> Double -> (Point, Double)
lineSearchWith (LineSearchOpts xtol alpha) func xold fold g pin stpmax = 
  go 1.0 Nothing
  where p = if pinnorm > stpmax then (stpmax/pinnorm) `scale` pin else pin
        pinnorm = norm pin
        slope = g `dot` p
        lammin = xtol / (maxabsratio p xold)
        
        go :: Double -> Maybe (Double,Double) -> (Point,Double)
        go lam pass = case check lam xnew fnew of
          Just xandf -> xandf
          Nothing -> 
            case pass of
              -- First time.
              Nothing -> go (lambound lam $ quadlam fnew) $ Just (lam,fnew)
              -- Subsequent times.
              Just val2 -> 
                go (lambound lam $ cubiclam fnew val2) $ Just (lam,fnew)
          where xnew = xold + lam `scale` p
                fnew = func xnew
                  
                -- Check for convergence or a "sufficiently large" step.
                check :: Double -> Vector Double -> Double -> 
                         Maybe (Vector Double,Double)
                check lam x f =
                  if lam < lammin then Just (xold,fold)
                  else if f <= fold + alpha * lam * slope then Just (x,f)
                       else Nothing
                  
                -- Keep step length within bounds.
                lambound lam lam' = max (0.1 * lam) (min lam' (0.5 * lam))
                
                -- Quadratic and cubic approximations to better step
                -- value.
                quadlam fnew = -slope / (2 * (fnew - fold - slope))
                cubiclam fnew (lam2,f2) =
                  if a == 0 
                  then (-slope / (2 * b))
                  else if disc < 0 then error "Roundoff problem in lineSearch"
                       else (-b + sqrt disc) / (3 * a)
                    where rhs1 = fnew - fold - lam * slope
                          rhs2 = f2 - fold - lam2 * slope
                          a = (rhs1 / lam^2 - rhs2 / lam2^2) / (lam - lam2)
                          b = (-lam2 * rhs1 / lam^2 + lam * rhs2 / lam2^2) / 
                              (lam - lam2)
                          disc = b^2 - 3 * a * slope


-- Utility functions for ratio testing.
--
absratio :: Double -> Double -> Double
absratio n d = abs n / (abs d `max` 1)

absratio' :: Double -> Double -> Double -> Double
absratio' scale n d = abs n / (abs d `max` 1) / scale

maxabsratio :: Vector Double -> Vector Double -> Double
maxabsratio n d = maxElement $ zipVectorWith absratio n d

maxabsratio' :: Double -> Vector Double -> Vector Double -> Double
maxabsratio' scale n d = maxElement $ zipVectorWith (absratio' scale) n d


--------------------------------------------------------------------------------
--
--  TEST FUNCTIONS
--

-- Simple test function.  Minimum at (3,4):
--
-- *BFGS> bfgs tstf1 tstgrad1 (fromList [-10,-10])
-- Right (fromList [3.0,4.0])
--
tstf1 :: Fn
tstf1 p = (x-3)^2 + (y-4)^2
  where [x,y] = toList p

tstgrad1 :: GradFn
tstgrad1 p = fromList [2*(x-3),2*(y-4)]
  where [x,y] = toList p


-- Rosenbrock's function.  Minimum at (1,1):
--
-- *BFGS> bfgs tstf2 tstgrad2 (fromList [-10,-10])
-- Right (fromList [0.9999999992103538,0.9999999985219549])

tstf2 :: Fn
tstf2 p = (1-x)^2 + 100*(y-x^2)^2
  where [x,y] = toList p

tstgrad2 :: GradFn
tstgrad2 p = fromList [2*(x-1) - 400*x*(y-x^2), 200*(y-x^2)]
  where [x,y] = toList p


-- Test function from Numerical Recipes.  Minimum at (-2.0,0.89442719):
--
-- *BFGS> bfgs tstfnr tstgradnr nrp0
-- Right (fromList [-1.9999999564447526,0.8944271925873616])

tstfnr :: Fn
tstfnr p = 10*(y^2*(3-x)-x^2*(3+x))^2+(2+x)^2/(1+(2+x)^2)
  where [x,y] = toList p

tstgradnr :: GradFn
tstgradnr p = fromList [20*(y^2*x3m-x^2*x3p)*(-y^2-6*x-3*x^2)+
                        2*x2p/(1+x2p^2)-2*x2p^3/(1+x2p^2)^2,
                        40*(y^2*x3m-x^2*x3p)*y*x3m]
  where [x,y] = toList p
	x3m = 3 - x
	x3p = 3 + x
	x2p = 2 + x

nrp0 :: Point
nrp0 = fromList [0.1,4.2]
