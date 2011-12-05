module Math.Probably.NelderMead where

import Math.Probably.FoldingStats
import Numeric.LinearAlgebra

import Data.Ord
import Data.List

{-mean, m2 :: Vector Double
mean = fromList [45.1,10.3]

cov :: Matrix Double
cov = (2><2) $ [5.0, 1,
                1, 1.5]

invCov = inv cov

lndet = log $ det cov

pdf = multiNormalByInv lndet invCov mean

m2 = fromList [55.1,20.3]

main = runRIO $ do
  io $ print $ pdf mean
  {-iniampar <- sample $ initialAdaMet 500 5e-3 (pdf) $ fromList [30.0,8.0]
  io $ print iniampar
  froampar <- runAndDiscard 5000 (show . ampPar) iniampar $ adaMet False (pdf)
  io $ print froampar
  io $ print $ realToFrac (count_accept froampar) / (realToFrac $ count froampar) -}
  let iniSim = genInitial (negate . pdf) 0.1 $ fromList [3.0,0.5]
  io $ mapM_ print iniSim
  let finalSim =  goNm (negate . pdf) 1 iniSim
  io $ print $ finalSim
  io $ print $ hessianFromSimplex (negate . pdf) finalSim -}

type Simplex = [(Vector Double, Double)]

centroid :: Simplex -> Vector Double
centroid points = scale (recip l) $ sum $ map fst points
    where l = fromIntegral $ length points

nmAlpha = 1
nmGamma = 2
nmRho = 0.5
nmSigma = 0.5

secondLast (x:y:[]) = x
secondLast (_:xs) = secondLast xs

replaceLast xs x = init xs ++ [x]

instance Bounded Double where
  minBound = -1e80
  maxBound = 1e80

--http://www.caspur.it/risorse/softappl/doc/sas_docs/ormp/chap5/sect28.htm
hessianFromSimplex :: (Vector Double -> Double) -> Simplex -> Matrix Double
hessianFromSimplex f sim = 
  let mat :: [Vector Double]
      mat = toRows $ fromColumns $ map fst sim
      swings' = flip map mat $ \vals -> runStat (meanF `both` minF `both` maxF) $ toList vals
      swings = flip map swings' $ \((y0, ymin),ymax) -> (y0, max (ymax-y0) (y0-ymin))
      n = length swings
      xv = fromList $ map fst swings
      fxv = f  xv
      units = flip map [0..n-1] $ \d -> buildVector n $ \i -> if i ==d then snd $ swings!!i else 0

      hess = buildMatrix n n $ \(i,j) ->(  (f $ xv + units!!i + units!!j)
                                         - (f $ xv + units!!i)
                                         - (f $ xv + units!!j)
                                         + (f xv) ) / (snd $ swings!!i) * (snd $ swings!!j)
      hess1= buildMatrix n n $ \(i,j) ->(  (f $ xv + units!!i + units!!j)
                                         - (f $ xv + units!!i - units!!j)
                                         - (f $ xv - units!!i + units!!j)
                                         + (f $ xv - units!!i - units!!j) ) / (4*(snd $ swings!!i) * (snd $ swings!!j))
  
  in inv hess1


genInitial :: (Vector Double -> Double) -> Double -> Vector Double -> Simplex
genInitial f h x0 = sim where
  n = length $ toList x0
  unit d = buildVector n $ \j -> if j ==d then h*x0@>d else 0.0
  mkv d = with f $ x0 + unit d
  sim = (x0, f x0) : map mkv [0..n-1] 

goNm :: (Vector Double -> Double) -> Double -> Simplex -> Simplex
goNm f' tol sim' = go f' $ sortBy (comparing snd) sim' where
  go f sim = let nsim = sortBy (comparing snd) $ (nmStep f sim)
             in if snd (last sim) - snd (head sim) < tol
                   then nsim
                   else go f nsim

nmStep :: (Vector Double -> Double) -> Simplex -> Simplex
nmStep f s0 = snext where
   x0 = centroid $ init s0
   xnp1 = fst (last s0)
   fxnp1 = snd (last s0)
   xr = x0 + nmAlpha * (x0 - xnp1)
   fxr = f xr
   fx1 = snd $ head s0
   snext = if fx1 <= fxr && fxr <= (snd $ secondLast s0)
              then replaceLast s0 (xr,fxr)
              else sexpand
   xe = x0 + nmGamma * (x0-xnp1)
   fxe = f xe
   sexpand = if fxr > fx1
                then scontract
                else if fxe < fxr
                        then replaceLast s0 (xe,fxe)
                        else replaceLast s0 (xr,fxr)
   xc = xnp1 + nmRho * (x0-xnp1)
   fxc = f xc
   scontract = if fxc < fxnp1
                  then replaceLast s0 (xc,fxc)
                  else sreduce
   sreduce = case s0 of 
              p0@(x1,_):rest -> p0 : (flip map rest $ \(xi,_) -> with f $ x1+nmRho * (xi-x1))

   
with f x = (x, f x)