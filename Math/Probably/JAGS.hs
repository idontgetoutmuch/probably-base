{-# LANGUAGE FlexibleInstances, OverloadedStrings #-}

module Math.Probably.JAGS where

import Control.Monad.Identity
import Data.List
import TNUtils
import Data.String
import System.Cmd
import Math.Probably.FoldingStats

data Model = Model [ModelLine]
              deriving (Show, Eq)

data Dist a = Beta a a
            | Exp a
            | Norm a a
            | Gamma a a
            | Binomial a a
            | Uniform a a
              deriving (Show, Eq)

data Expr = Var String
          | Const Double
          | M1 String Expr
          | M2 Op2 Expr Expr
          | If Expr Expr Expr
          | Cmp CmpOp Expr Expr
          | CalcStat Stat Expr
            deriving (Show,Eq)
--          | Dist (Dist Expr)

data Node = StochNode (Dist Expr)
          | DetNode Expr
            deriving (Show, Eq)

data Op2 = Add | Sub | Mul | Div deriving (Show, Eq)
data CmpOp = Lt | Gt | Eq deriving (Show, Eq)

data Stat = Mean deriving (Show, Eq)

data ModelLine = ForEvery String Expr Expr [ModelLine]
               | MkNode String Node
                 deriving (Show, Eq)

ppDE (Beta x y) = "dbeta("++ppE x++", "++ppE y ++")"
ppDE (Norm x y) = "dnorm("++ppE x++", "++ppE y ++")"
ppDE (Gamma x y) = "dgamma("++ppE x++", "++ppE y ++")"
ppDE (Binomial x y) = "dbin("++ppE x++", "++ppE y ++")"
ppDE (Uniform x y) = "dunif("++ppE x++", "++ppE y ++")"

ppE (Var s) = s
ppE (Const x) = show x
ppE (M2 op e1 e2) = "("++ppE e1++") "++ ppOp2 op++" ("++ppE e2++")"
ppE (M1 f e) = f++"("++ppE e++")"
ppE (CalcStat s e) = showStat s ++ "("++ppE e++")"

ppOp2 Add = "+" 
ppOp2 Sub = "-" 
ppOp2 Mul = "*"
ppOp2 Div = "/"

showStat Mean = "mean"

infix 1 <--
infix 1 ~~
 
nm <-- e = MkNode nm $ DetNode e
nm ~~ d = MkNode nm $ StochNode d

mean = CalcStat Mean

class RDump a where
    rdump :: String -> a -> String

instance Show a => RDump [a] where
    rdump nm xs = nm++" <-\nc("++(intercalate ", " $ map show xs)++")\n"

regressModel = Model
                  [ForEvery "i" 1 5 [
                    "Y[i]" ~~ Norm "mu[i]" "tau",
                    "mu[i]" <-- "alpha" + "beta" * ("x[i]" - "xbar")
                    ],
                   "xbar" <-- mean "x",
                   "sigma" <-- 1/sqrt "tau",
                   "alpha" ~~ Norm 0 0.0001,
                   "tau" ~~ Gamma 0.001 0.001,
                   "beta" ~~ Norm 0 0.0001
                  ]

modelToJags :: Model -> String
modelToJags (Model lns) = 
    runIdentity $ execCodeWriterNotHsT $ do 
      tell "model {"
      indent 3
      forM lns $ tellLine 
      indent $ -3
      tell "}"

runModel :: Model -> Int -> Int -> [(String, [Double])] -> [String] -> IO [(String, Double, Double)]
runModel m burn iters obs monits = do
  writeFile "jagsmodel" $ modelToJags m
  writeFile "jagsdata" $ concatMap (uncurry rdump) obs
  writeFile "jagsscript" $ unlines $ 
                ["model in jagsmodel",
                 "data in jagsdata",
                 "compile", "initialize",
                 "update "++show burn]
                ++ map ("monitor "++) monits++
                ["update "++show iters]++ map (\v->"coda "++v++", stem("++v++")") monits
  system "jags jagsscript"
  forM monits $ \m -> do 
    lst <- (map (read .  dropWhile (==' ') . (dropWhile (/=' '))) .  lines) `fmap` readFile (m++"chain1.txt")
    let (mu,sd) = runStat meanSDF lst 
    return (m, mu, sd)
  


--Unable to evaluate upper index of counter

showIdx Nothing = ""
showIdx (Just s) = "["++s++"]"

ppEFor (Const x) = show $ round x
ppEFor e = ppE e

tellLine (MkNode nm (DetNode e)) = tell $ nm++" <- "++ppE e
tellLine (MkNode nm (StochNode e)) = tell $ nm++" ~ "++ppDE e
tellLine (ForEvery n n1 n2 lns) = do
  tell $ "for ("++n++" in "++ppEFor n1++":"++ppEFor n2++") {"
  indent 3
  forM lns $ tellLine 
  indent $ -3
  tell "}"
         
tstData = [("x", [1,2,3,4,5]),
           ("Y", [1,3,3,3,5])]
          

tst = runModel regressModel 1000 1000 tstData ["alpha", "beta"]
                 

instance Num Expr where
    (+) = M2 Add
    (-) = M2 Sub
    (*) = M2 Mul
    abs e = If (Cmp Gt e 0) e (negate e) 
    signum e = If (Cmp Gt e 0) 1 (negate 1) 
    fromInteger i = Const $ realToFrac i


instance Fractional Expr where
    fromRational r = Const $ realToFrac r
    (/) = M2 Div

instance Floating Expr where
    sqrt = M1 "sqrt"
    pi = Const pi
    exp = M1 "exp"
    log = M1 "ln"
    sin = M1 "sin"
    cos = M1 "cos"
    asin = M1 "asin"
    acos = M1 "acos"
    sinh = M1 "sinh"
    cosh = M1 "cosh"
    atan = M1 "atan"
    asinh = M1 "asinh"
    acosh = M1 "acosh"
    atanh = M1 "atanh"
    


instance IsString Expr where
    fromString = Var