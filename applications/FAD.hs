module FAD where

import Data.Number.IReal
import Data.Number.IReal.Powers
import ListNumSyntax

{- 

Simple forward automatic differentiation. The main reason for supplying this
module rather than using one of several similar alternatives available on Hackage 
is that they all seem to use the following implementation of differentiation of 
products (in our notation):

x * y = mkDif (val x * val y) (df 1 x * y + x * df 1 y)

This is elegant but exponential in the order of differentiation, and hence
unsuitable for much of validated numerics, which often uses moderately high
order derivatives. 

In our implementation, high order derivatives are still slow, but not as bad.

-}

newtype Dif a = D [a] deriving Show

-- constructing Dif values -----------------------------------------------------

con, var :: Num a => a -> Dif a
con c = D [c] 
var x = D [x,1]

mkDif :: a -> Dif a -> Dif a
mkDif x (D xs) = D (x:xs)

-- selectors ------------------------------------------------------------------

val :: Num a => Dif a -> a
val (D []) = 0
val (D (x:_)) = x

fromDif :: Num a => Dif a -> [a]
fromDif (D xs) = xs

unDif :: (Num a, Num b) => (Dif a -> Dif b) -> a -> b
unDif f = val . f . var

-- differentiation ------------------------------------------------------------

df :: Int -> Dif a -> Dif a
df n (D xs) = D (drop n xs)

deriv :: (Num a, Num b) => Int -> (Dif a -> Dif b) -> a -> b
deriv n f = unDif (df n . f)

derivs :: (Num a, Num b) => (Dif a -> Dif b) -> a -> [b]
derivs f = fromDif . f . var

chain, rchain :: Num a => (a -> a) -> (Dif a -> Dif a) -> Dif a -> Dif a
chain f f' g = mkDif (f (val g)) (df 1 g * f' g)

rchain f f' g = r where r = mkDif (f (val g)) (df 1 g * f' r)

r2chain :: Num a => (a -> a) -> (a -> a) -> (Dif a -> Dif a) ->
                    (Dif a -> Dif a) -> Dif a -> Dif a
r2chain f1 f2 f1' f2' g = x 
  where g' = df 1 g
        x = mkDif (f1 (val g)) (g' * f1' y)
        y = mkDif (f2 (val g)) (g' * f2' x)

-- instances -------------------------------------------------------------------

instance VarPrec a => VarPrec (Dif a) where
  precB b (D xs) = D (map (precB b) xs)

instance (Num a, Eq a) => Eq (Dif a) where
  x==y          = val x == val y

instance (Num a, Ord a) => Ord (Dif a) where
  compare x y   = compare (val x) (val y)

instance  Num a => Num (Dif a) where
   x + y        = mkDif (val x + val y) (df 1 x + df 1 y)
   x * y        = D (convs (fromDif x) (fromDif y)) 
   abs          = chain abs signum       -- wrong for argument 0
   negate       = chain negate (const (-1))
   signum       = chain signum (const 0) -- wrong for argument 0
   fromInteger  = con . fromInteger

instance (Fractional a, Powers a) => Fractional (Dif a) where
   recip g      = r where r = mkDif (recip (val g)) (-df 1 g * sq r)
   fromRational = con . fromRational

instance (Floating a, Powers a) => Floating (Dif a) where 
   pi       = con pi
   exp      = rchain exp id
   log      = chain log recip
   sqrt     = rchain sqrt (recip . (*2))
   sin      = r2chain sin cos id negate
   cos      = r2chain cos sin negate id
   tan      = rchain tan ((1+) . sq)
   asin     = chain asin (recip . sqrt . (1-) . sq)
   acos     = chain acos (negate . recip . sqrt . (1-) . sq)
   atan     = chain atan (recip . (1+) . sq)
   sinh     = r2chain sinh cosh id id
   cosh     = r2chain cosh sinh id id
   asinh    = chain asinh (recip . sqrt . (1+) . sq)
   acosh    = chain acosh (recip . sqrt . (\x -> x-1) . sq)
   atanh    = chain atanh (recip . (1-) . sq) 

instance (Num a, Powers a) => Powers (Dif a) where
   sq       = chain sq (2*)
   pow x 0  = con 1
   pow x n  = chain (flip pow n) ((fromIntegral n *) . flip pow (n-1)) x 
   -- Note: This is linear in n, but behaves correctly on intervals

instance Real a => Real (Dif a) where
  toRational = toRational . val

instance (Powers a, RealFrac a) => RealFrac (Dif a) where
    -- discontinuities ignored
    properFraction x = (i, x - fromIntegral i) where (i, _) = properFraction (val x)
    truncate = truncate . val
    round    = round    . val
    ceiling  = ceiling  . val
    floor    = floor    . val

instance ( Powers a, RealFloat a) => RealFloat (Dif a) where
    floatRadix = floatRadix . val
    floatDigits = floatDigits . val
    floatRange = floatRange . val
    exponent = exponent . val
    scaleFloat n (D xs) = D (map (scaleFloat n) xs)
    isNaN = isNaN . val
    isInfinite = isInfinite . val
    isDenormalized = isDenormalized . val
    isNegativeZero = isNegativeZero . val
    isIEEE = isIEEE . val
    decodeFloat = decodeFloat . val
    encodeFloat m e = con (encodeFloat m e)

convs [] _ = []
convs (x:xs) ys = convs' [1] [x] xs ys
  where convs' _ _ _ [] = []
        convs' ps ars as bs = sum (ps * ars * bs) 
                            : case as of
                                a:as' -> convs' (next ps) (a:ars) as' bs
                                [] -> convs'' (next ps) ars 1 bs
        convs'' ps ars n bs = case bs of
                                 _:bs' -> sum (drop n ps * ars * bs')  
                                           : convs'' (next ps) ars (n+1) bs'
                                 [] -> []
        next xs = 1 : (xs + tail xs) ++ [1] -- next row in Pascal's triangle
