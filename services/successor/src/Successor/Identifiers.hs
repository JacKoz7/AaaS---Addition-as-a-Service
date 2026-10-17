-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Identifiers
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Random bytes, lowercase hexadecimal, UUIDv7 identifiers
--                  and the AaaS timestamp format.
-- Related Docs:    RFC 9562 (UUIDv7), ADR-0013 (identifier and timestamp
--                  formats), ADR-0016

-- | Identifiers and timestamps.
--
-- __Description:__ Event identifiers are lowercase UUIDv7 (RFC 9562, 5.7)
-- and timestamps are UTC with exactly three fractional digits and @Z@
-- (ADR-0013). Randomness comes from @\/dev\/urandom@.
--
-- __Business Justification:__ Every event the service publishes needs a
-- unique, time-ordered @eventId@ and an @occurredAt@ in the shared form.
--
-- __Thread Safety:__ safe; every call opens its own handle on the random
-- source.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Successor.Identifiers
  ( randomBytes,
    hex,
    uuidV7FromParts,
    newUuidV7,
    isUuid,
    formatTimestamp,
    nowMillis,
  )
where

import Data.Bits (shiftR, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isDigit, isHexDigit, isLower)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time.Clock.POSIX (getPOSIXTime, posixSecondsToUTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Word (Word8)
import System.IO (IOMode (ReadMode), withBinaryFile)
import Text.Printf (printf)

-- | Reads random bytes from the kernel CSPRNG.
--
-- __Description:__ Opens @\/dev\/urandom@, reads exactly @count@ bytes and
-- closes it.
--
-- __Business Justification:__ Random bits of UUIDv7 and span identifiers.
--
-- __Parameters:__
--
-- * @count@: number of bytes, @>= 0@.
--
-- __Returns:__ @count@ random bytes.
--
-- __Errors:__ an 'IOError' if the random source cannot be read.
--
-- __Side Effects:__ reads @\/dev\/urandom@.
--
-- __Complexity:__ O(count).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @BS.length \<$\> randomBytes 16@ is @16@.
--
-- __See Also:__ 'newUuidV7'.
randomBytes :: Int -> IO ByteString
randomBytes count =
  withBinaryFile "/dev/urandom" ReadMode (`BS.hGet` count)

-- | Lowercase hexadecimal form of bytes.
--
-- __Description:__ Two characters per byte, most significant nibble first.
--
-- __Business Justification:__ Identifiers in AaaS are lowercase hex
-- (ADR-0013).
--
-- __Parameters:__
--
-- * @bytes@: the bytes.
--
-- __Returns:__ their hexadecimal text.
--
-- __Errors:__ None.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(n).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__
--
-- >>> hex (BS.pack [1, 171])
-- "01ab"
--
-- __See Also:__ 'uuidV7FromParts'.
hex :: ByteString -> Text
hex = Text.pack . concatMap (printf "%02x") . BS.unpack

-- | Builds a UUIDv7 from a timestamp and random bytes.
--
-- __Description:__ 48 bits of Unix milliseconds (big-endian), then the
-- first 10 bytes of @random@ with the version nibble set to @7@ and the
-- variant bits to @10@, in the 8-4-4-4-12 form.
--
-- __Business Justification:__ Deterministic core of 'newUuidV7', testable
-- with fixed inputs.
--
-- __Parameters:__
--
-- * @millis@: milliseconds since the Unix epoch, @0 <= millis < 2^48@.
-- * @random@: at least 10 bytes; extra bytes are ignored.
--
-- __Returns:__ the UUID text, or 'Nothing' if @random@ is too short.
--
-- __Errors:__ 'Nothing' for fewer than 10 random bytes.
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
-- >>> uuidV7FromParts 0x018f3c2e7b1a (BS.replicate 10 0)
-- Just "018f3c2e-7b1a-7000-8000-000000000000"
--
-- __See Also:__ 'newUuidV7', 'isUuid'.
uuidV7FromParts :: Integer -> ByteString -> Maybe Text
uuidV7FromParts millis random
  | BS.length random < 10 = Nothing
  | otherwise = Just (dashed (hex bytes))
  where
    time = [fromIntegral ((millis `shiftR` (8 * k)) .&. 0xff) | k <- [5, 4 .. 0]] :: [Word8]
    rest = BS.unpack (BS.take 10 random)
    bytes = case rest of
      (r0 : r1 : r2 : rs) -> BS.pack (time ++ [0x70 .|. (r0 .&. 0x0f), r1, 0x80 .|. (r2 .&. 0x3f)] ++ rs)
      _ -> BS.pack time
    dashed t =
      Text.intercalate
        "-"
        [Text.take 8 t, slice 8 4 t, slice 12 4 t, slice 16 4 t, Text.drop 20 t]
    slice from len = Text.take len . Text.drop from

-- | Generates a UUIDv7 for the current time.
--
-- __Description:__ 'uuidV7FromParts' with 'nowMillis' and 10 bytes of
-- 'randomBytes'.
--
-- __Business Justification:__ The @eventId@ of every published event.
--
-- __Parameters:__ None.
--
-- __Returns:__ a new lowercase UUIDv7.
--
-- __Errors:__ an 'IOError' from 'randomBytes'.
--
-- __Side Effects:__ reads the clock and the random source.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @Text.index \<$\> newUuidV7 \<*\> pure 14@ is @\'7\'@.
--
-- __See Also:__ 'uuidV7FromParts'.
newUuidV7 :: IO Text
newUuidV7 = do
  millis <- nowMillis
  random <- randomBytes 10
  maybe (ioError (userError "uuidV7: short random read")) pure (uuidV7FromParts millis random)

-- | Tests whether a text is a lowercase canonical UUID.
--
-- __Description:__ 8-4-4-4-12 lowercase hexadecimal digits, any version.
--
-- __Business Justification:__ Validation of the @taskId@ of a request.
--
-- __Parameters:__
--
-- * @t@: the candidate.
--
-- __Returns:__ 'True' for a lowercase canonical UUID.
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
-- >>> isUuid "018f3c2e-7b1a-7c3d-9f00-0000000000aa"
-- True
-- >>> isUuid "018F3C2E-7B1A-7C3D-9F00-0000000000AA"
-- False
--
-- __See Also:__ 'uuidV7FromParts'.
isUuid :: Text -> Bool
isUuid t =
  map Text.length groups == [8, 4, 4, 4, 12]
    && all (Text.all (\c -> isHexDigit c && (isDigit c || isLower c))) groups
  where
    groups = Text.splitOn "-" t

-- | Formats Unix milliseconds in the AaaS timestamp form.
--
-- __Description:__ @YYYY-MM-DDTHH:MM:SS.mmmZ@ in UTC.
--
-- __Business Justification:__ The only form the event schemas accept.
--
-- __Parameters:__
--
-- * @millis@: milliseconds since the epoch, non-negative.
--
-- __Returns:__ the timestamp text.
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
-- >>> formatTimestamp 1792152000000
-- "2026-10-16T12:00:00.000Z"
-- >>> formatTimestamp 7
-- "1970-01-01T00:00:00.007Z"
--
-- __See Also:__ 'nowMillis'.
formatTimestamp :: Integer -> Text
formatTimestamp millis =
  Text.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S" utc)
    <> Text.pack (printf ".%03dZ" (millis `mod` 1000))
  where
    utc = posixSecondsToUTCTime (fromInteger (millis `div` 1000))

-- | Current wall-clock time in Unix milliseconds.
--
-- __Description:__ The POSIX time truncated to milliseconds.
--
-- __Business Justification:__ @occurredAt@, @calledAt@ and the UUIDv7
-- timestamp.
--
-- __Parameters:__ None.
--
-- __Returns:__ milliseconds since 1970-01-01T00:00:00Z.
--
-- __Errors:__ None.
--
-- __Side Effects:__ reads the clock.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @(> 1700000000000) \<$\> nowMillis@ is 'True'.
--
-- __See Also:__ 'formatTimestamp'.
nowMillis :: IO Integer
nowMillis = floor . (* 1000) <$> getPOSIXTime
