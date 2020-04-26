{-# LANGUAGE DeriveFunctor, TypeFamilies, GADTs, RankNTypes #-}
{-# LANGUAGE GeneralizedNewtypeDeriving, ScopedTypeVariables, LambdaCase #-}
-----------------------------------------------------------------------------
-- |
-- Module     : Control.Match
-- Copyright  : (c) Andrey Mokhov 2018-2020
-- License    : MIT (see the file LICENSE)
-- Maintainer : andrey.mokhov@gmail.com
-- Stability  : experimental
--
-- An experiment in expressing Applicative, Selective and Monad using the Match
-- type class.
-----------------------------------------------------------------------------
module Control.Match where

import Control.Applicative ((<**>))
import Data.Functor.Const
import Data.Kind
import Prelude hiding (pure)

-- | A generalised sum type where @t@ stands for the type of constructor "tags".
-- Each tag has a type parameter @x@ which determines the type of the payload.
-- A 'Sigma' @t@ value therefore contains a payload whose type is not visible
-- externally but is revealed when pattern-matching on the tag.
--
-- See 'Two', 'eitherToSigma' and 'sigmaToEither' for an example.
data Sigma t where
    Sigma :: t x -> x -> Sigma t

-- | A data type defining no tags. Similar to 'Data.Void.Void' but parameterised.
data Zero a where

-- | A data type with a single tag. This data type is commonly known as @Refl@,
-- see "Data.Type.Equality".
data One a b where
    One :: One a a

-- | A data type with two tags 'A' and 'B' that allows us to encode the good old
-- 'Either' as 'Sigma' 'Two', where the tags 'A' and 'B' correspond to 'Left'
-- and 'Right', respectively. See 'eitherToSigma' and 'sigmaToEither' that
-- witness the isomorphism between 'Either' @a b@ and 'Sigma' @(@'Two'@ a b)@.
data Two a b c where
    A :: Two a b a
    B :: Two a b b

-- | Encode 'Either' into a generalised sum type.
eitherToSigma :: Either a b -> Sigma (Two a b)
eitherToSigma = \case
    Left  a -> Sigma A a
    Right b -> Sigma B b

-- | Decode 'Either' from a generalised sum type.
sigmaToEither :: Sigma (Two a b) -> Either a b
sigmaToEither = \case
    Sigma A a -> Left  a
    Sigma B b -> Right b

-- | A potentially uncountable collection of tags for the same unit @()@ payload.
data Many a b where
    Many :: a -> Many a ()

many :: a -> Sigma (Many a)
many a = Sigma (Many a) ()

-- | Hide the type of the payload a tag.
--
-- There is a whole library dedicated to this nice little GADT:
-- http://hackage.haskell.org/package/some.
data Some t where
    Some :: t a -> Some t

-- | A class of tags with no constraint.
class Unconstrained (t :: * -> *) where

instance Unconstrained Zero where
instance Unconstrained (One a) where
instance Unconstrained (Two a b) where
instance Unconstrained (Many a) where

-- | A class of tags that can be enumerated.
--
-- A valid instance must list every tag in the resulting list exactly once.
class Unconstrained t => Countable t where
    enumerate :: [Some t]

instance Countable Zero where
    enumerate = []

instance Countable (One a) where
    enumerate = [Some single]

instance Countable (Two a b) where
    enumerate = [Some A, Some B]

-- | Like 'Countable' but the list has finite length.
class Countable t => Finite t where

instance Finite Zero where
instance Finite (One a) where
instance Finite (Two a b) where

-- | Like 'Finite' but the list has length equal to one, so @enumerate@ must be
-- equal to @[Some single]@.
class Finite t => Single t where
    type Payload t
    single :: t (Payload t)
    matchSingle :: Sigma t -> Payload t

instance Single (One a) where
    type Payload (One a) = a
    single = One
    matchSingle (Sigma One x) = x

-- | Generalised pattern matching on a Sigma type using a Pi type to describe
-- how to handle each case.
matchPure :: Sigma t -> (forall x. t x -> x -> a) -> a
matchPure (Sigma t x) pi = pi t x

-- | A type class that allows lifting 'matchPure' into an effect 'f'.
class Functor f => Match f where
    type Tag f :: (* -> *) -> Constraint
    pure  :: a -> f a
    match :: Tag f t => f (Sigma t) -> (forall x. t x -> f (x -> a)) -> f a

fmapLike :: (Match f, Tag f (One a)) => a -> f (a -> b) -> f b
fmapLike a f = match (pure (Sigma One a)) (\One -> f)

apply :: (Match f, Tag f (One a)) => f (a -> b) -> f a -> f b
apply f x = match (Sigma One <$> x) (\One -> f)

select :: (Match f, Tag f (Two a b)) => f (Either a b) -> f (a -> b) -> f b
select x f = match (eitherToSigma <$> x) $ \case
    A -> f
    B -> pure id

bind :: (Match f, Tag f (Many a)) => f a -> (a -> f b) -> f b
bind x f = match (many <$> x) (\(Many x) -> const <$> f x)

-- | Any applicative can be given a 'Match' instance.
newtype MatchA f a = MatchA { getMatchA :: f a }
    deriving (Functor, Applicative)

instance Applicative f => Match (MatchA f) where
    type Tag (MatchA f) = Single
    pure = pure
    match = matchA

-- | Any monad can be given a 'Match' instance.
newtype MatchM f a = MatchM { getMatchM :: f a }
    deriving (Functor, Applicative, Monad)

instance Monad f => Match (MatchM f) where
    type Tag (MatchM f) = Unconstrained
    pure = return
    match = matchM

matchA :: (Applicative f, Single t) => f (Sigma t) -> (forall x. t x -> f (x -> a)) -> f a
matchA sigma pi = matchSingle <$> sigma <**> pi single

instance Monoid m => Match (Const m) where
    type Tag (Const m) = Single
    pure _ = Const mempty
    match (Const x) pi = Const (mappend x y)
      where
        y = getConst (pi single)

matchM :: Monad f => f (Sigma t) -> (forall x. t x -> f (x -> a)) -> f a
matchM sigma pi = sigma >>= \(Sigma t x) -> ($x) <$> pi t

instance Match Maybe where
    type Tag Maybe = Unconstrained
    pure  = Just
    match = matchM