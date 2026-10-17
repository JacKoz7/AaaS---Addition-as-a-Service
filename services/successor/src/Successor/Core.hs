-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Core
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Computes the successor of a natural number in the range
--                  of the AaaS addition.
-- Related Docs:    services/successor/docs/SERVICE_CHARTER.md, CLAUDE.md 1
--                  (rule 5) and 3 (step 7), ADR-0016

-- | The successor function @S(n) = n + 1@ of Peano arithmetic.
--
-- __Description:__ The domain is @0 .. 199 997@: the largest sum of two
-- operands is @99 999 + 99 999 = 199 998@, so no successor call of an
-- addition ever needs a larger argument.
--
-- __Business Justification:__ An addition @a + b@ is @b@ applications of
-- this function to @a@ (CLAUDE.md 1, rule 5). It is the heart of the
-- product.
--
-- __Thread Safety:__ pure; safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Successor.Core
  ( maxArgument,
    NextError (..),
    next,
    describeError,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

-- | Largest argument accepted by 'next'.
--
-- __Description:__ @199 997@, so that the result never exceeds the largest
-- possible sum, @199 998@ (the @sum@ definition of the event envelope).
--
-- __Business Justification:__ A call outside the range of an addition is
-- a defect of the caller and is reported instead of computed.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- >>> maxArgument
-- 199997
maxArgument :: Integer
maxArgument = 199997

-- | Why a successor cannot be computed.
--
-- __Description:__ 'Negative' for @n < 0@ (not a natural number);
-- 'AboveRange' for @n > 'maxArgument'@.
--
-- __Business Justification:__ Distinct reasons in the problem detail of
-- the API.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data NextError
  = -- | The argument is below zero.
    Negative Integer
  | -- | The argument is above 'maxArgument'.
    AboveRange Integer
  deriving stock (Eq, Show)

-- | Computes @n + 1@.
--
-- __Description:__ Checks the domain and returns the successor. The
-- computation is native for now; step P2.13 replaces it with the digit
-- services and the carry service.
--
-- __Business Justification:__ See the module documentation.
--
-- __Parameters:__
--
-- * @n@: natural number in @[0, 199997]@.
--
-- __Returns:__ @Right (n + 1)@.
--
-- __Errors:__ @Left ('Negative' n)@ or @Left ('AboveRange' n)@ outside the
-- domain.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(1) time and memory.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__
--
-- >>> next 199
-- Right 200
-- >>> next 199998
-- Left (AboveRange 199998)
--
-- __See Also:__ 'Successor.Service.call', CLAUDE.md 4.3 (@Next@).
next :: Integer -> Either NextError Integer
next n
  | n < 0 = Left (Negative n)
  | n > maxArgument = Left (AboveRange n)
  -- TEMPORARY(P2.13): n + 1 is computed natively until successor queries
  -- the digit services and the carry service.
  | otherwise = Right (n + 1)

-- | Human-readable description of a 'NextError'.
--
-- __Description:__ One English sentence fragment naming the argument and
-- the domain.
--
-- __Business Justification:__ The @detail@ of the RFC 9457 problem.
--
-- __Parameters:__
--
-- * @err@: the error.
--
-- __Returns:__ the description.
--
-- __Errors:__ None.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__
--
-- >>> describeError (Negative (-1))
-- "n = -1 is not a natural number"
--
-- __See Also:__ 'next'.
describeError :: NextError -> Text
describeError = \case
  Negative n -> "n = " <> tshow n <> " is not a natural number"
  AboveRange n ->
    "n = "
      <> tshow n
      <> " is above "
      <> tshow maxArgument
      <> ", the largest argument of an addition"
  where
    tshow = Text.pack . show
