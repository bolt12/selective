# Selective applicative functors

This is a study of *selective applicative functors*, an abstraction between `Applicative` and `Monad`:

```haskell
-- Law: If fmap Left x /= fmap Right x then
--      * handle f (fmap Left  x) == f <*> x
--      * handle f (fmap Right x) == x
--
-- For example, when f = Maybe we have:
--      * handle f (Just (Left  a)) == f <*> x
--      * handle f (Just (Right b)) == x
--      * handle f Nothing is not constrained, allowing the implementation to
--        select between the two above behaviours. The default implementation
--        provided for a Monad f skips the effect: handle f Nothing = Nothing.
class Applicative f => Selective f where
    handle :: f (a -> b) -> f (Either a b) -> f b
```

You can think of `handle` as a *selective function application*: you apply the
function only when given a value of type `Left a`. Otherwise, you skip it (along
with all its effects) and return the `b` from `Right b`. Intuitively, `handle`
allows you to *efficiently* handle an error, which we often represent by `Left a`
in Haskell.

Note that you can write a function with this type signature using `Applicative`,
but it will have different behaviour -- it will always execute the effects
associated with the handler, hence being less efficient.

```haskell
handleA :: Applicative f => f (a -> b) -> f (Either a b) -> f b
handleA f x = either <$> f <*> pure id <*> x
```

`Selective` is more powerful than `Applicative`: you can recover the
application operator `<*>` as follows.

```haskell
apS :: Selective f => f (a -> b) -> f a -> f b
apS f = handle f . fmap Left
```

The `select` function is a natural generalisation of `handle`: instead of
skipping one unnecessary effect, it selects which of the two given effectful
functions to apply to a given argument. It is possible to implement `select` in
terms of `handle`, which is a good puzzle (give it a try!):

```haskell
select :: Selective f => f (a -> c) -> f (b -> c) -> f (Either a b) -> f c
select = ... -- Try to figure out the implementation!
```

Finally, any `Monad` is `Selective`:

```haskell
handleM :: Monad f => f (a -> b) -> f (Either a b) -> f b
handleM mf mx = do
    x <- mx
    case x of
        Left  a -> fmap ($a) mf
        Right b -> pure b
```

Selective functors are sufficient for implementing many conditional constructs,
which traditionally require the (much more powerful) `Monad` type class.
For example:

```haskell
-- | Branch on a Boolean value, skipping unnecessary effects.
ifS :: Selective f => f Bool -> f a -> f a -> f a
ifS i t f = select (fmap const f) (fmap const t) $
    fmap (\b -> if b then Right () else Left ()) i

-- | Conditionally apply an effect.
whenS :: Selective f => f Bool -> f () -> f ()
whenS x act = ifS x act (pure ())

-- | Keep checking a given effectful condition while it holds.
whileS :: Selective f => f Bool -> f ()
whileS act = whenS act (whileS act)

-- | A lifted version of lazy Boolean OR.
(<||>) :: Selective f => f Bool -> f Bool -> f Bool
(<||>) a b = ifS a (pure True) b

-- | A lifted version of 'any'. Retains the short-circuiting behaviour.
anyS :: Selective f => (a -> f Bool) -> [a] -> f Bool
anyS p = foldr ((<||>) . p) (pure False)
```

See more examples in [src/Control/Selective.hs](src/Control/Selective.hs).