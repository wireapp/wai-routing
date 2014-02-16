-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies          #-}

module Network.Wai.Routing.Predicate.Header
    ( Hdr    (..)
    , HasHdr (..)
    ) where

import Control.Applicative
import Data.ByteString (ByteString)
import Data.ByteString.From
import Data.CaseInsensitive (mk)
import Data.List (find)
import Data.Maybe
import Data.Monoid
import Network.HTTP.Types.Status
import Network.Wai.Routing.Error
import Network.Wai.Routing.Internal
import Network.Wai.Routing.Predicate.Predicate
import Network.Wai.Routing.Request

newtype Hdr a = Hdr ByteString

instance (Applicative m, FromByteString a) => Predicate m (Hdr a) Req where
    type FVal (Hdr a) = Error
    type TVal (Hdr a) = a
    apply (Hdr x)     =
        let msg = "Missing header '" <> x <> "'." in
        pure . rqApply (lookupHeader x) readValues (err status400 msg)

newtype HasHdr = HasHdr ByteString

instance Applicative m => Predicate m HasHdr Req where
    type FVal HasHdr   = Error
    type TVal HasHdr   = ()
    apply (HasHdr x) r = pure $
        if isJust $ find ((mk x ==) . fst) (headers r)
            then T 0 ()
            else F (err status400 ("Missing header '" <> x <> "'."))

