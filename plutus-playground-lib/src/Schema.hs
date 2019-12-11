{-# LANGUAGE AllowAmbiguousTypes        #-}
{-# LANGUAGE DefaultSignatures          #-}
{-# LANGUAGE DeriveAnyClass             #-}
{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}

-- | For the Playground, we need to be able to represent function
-- signatures, and function calls, as JSON objects.
--
-- 'ToSchema' turns a function signature into a 'FormSchema' - a
-- description that can serialised as JSON and analysed in PureScript
-- land. In essence it's a simplified, specialised version of a
-- 'Generic' representation.
--
-- The frontend then takes a 'FormSchema', generates a UI form, and
-- allows the user create a concrete value that follows that
-- schema. This is the 'FormArgument'.
--
-- It's useful for the backend to make this instantiation too (because
-- we want to give the user example filled-in forms), so we provide
-- ToArgument.
module Schema
    ( ToSchema
    , toSchema
    , FormSchema(..)
    , ToArgument
    , toArgument
    , FormArgument
    , FormArgumentF(..)
    , formArgumentToJson
    ) where

import           Crypto.Hash                (Digest, SHA256)
import           Data.Aeson                 (FromJSON, ToJSON, toJSON)
import qualified Data.Aeson                 as JSON
import           Data.Bifunctor             (first)
import           Data.Eq.Deriving           (deriveEq1)
import           Data.Functor.Foldable      (Fix (Fix), cata)
import qualified Data.HashMap.Strict        as HashMap
import qualified Data.Map
import           Data.Monoid                ((<>))
import           Data.Proxy                 (Proxy)
import           Data.Text                  (Text)
import qualified Data.Text                  as Text
import           GHC.Generics               ((:*:) ((:*:)), (:+:), C1, Constructor, D1, Generic, K1 (K1), M1 (M1), Rec0,
                                             Rep, S1, Selector, U1, conIsRecord, conName, from, selName)
import qualified Language.PlutusTx.AssocMap
import qualified Language.PlutusTx.Prelude  as P
import           Ledger                     (Ada, CurrencySymbol, DataScriptHash, Interval, PubKey, RedeemerHash,
                                             Signature, Slot, SlotRange, TokenName, ValidatorHash, Value)
import           LedgerBytes                (LedgerBytes)
import           Wallet.Emulator.Wallet     (Wallet)

import           Text.Show.Deriving         (deriveShow1)

{-# ANN module ("HLint: ignore Avoid restricted function" :: Text)
        #-}

data FormSchema
    = FormSchemaUnit
    | FormSchemaBool
    | FormSchemaInt
    | FormSchemaString
    | FormSchemaHex
    | FormSchemaArray FormSchema
    | FormSchemaMaybe FormSchema
    | FormSchemaRadio [String]
    | FormSchemaTuple FormSchema FormSchema
    | FormSchemaObject [(String, FormSchema)]
    -- Blessed types that get their own special UI widget.
    | FormSchemaValue
    | FormSchemaSlotRange
    -- Exceptions.
    | FormSchemaUnsupported String
    deriving (Show, Eq, Generic)
    deriving anyclass (FromJSON, ToJSON)

------------------------------------------------------------
type FormArgument = Fix FormArgumentF

data FormArgumentF a
    = FormUnitF
    | FormBoolF Bool
    | FormIntF (Maybe Int)
    | FormStringF (Maybe String)
    | FormHexF (Maybe String)
    | FormRadioF [String] (Maybe String)
    | FormArrayF FormSchema [a]
    | FormMaybeF FormSchema (Maybe a)
    | FormTupleF a a
    | FormObjectF [(String, a)]
    | FormValueF Value
    | FormSlotRangeF (Interval Slot)
    | FormUnsupportedF String
    deriving (Show, Generic, Eq, Functor)
    deriving anyclass (ToJSON, FromJSON)

deriving newtype instance ToJSON (Fix FormArgumentF)

deriving newtype instance FromJSON (Fix FormArgumentF)

formArgumentToJson :: Fix FormArgumentF -> Maybe JSON.Value
formArgumentToJson = cata algebra
  where
    algebra :: FormArgumentF (Maybe JSON.Value) -> Maybe JSON.Value
    algebra FormUnitF = justJSON ()
    algebra (FormBoolF v) = justJSON v
    algebra (FormIntF v) = justJSON v
    algebra (FormStringF v) = justJSON v
    algebra (FormHexF v) = justJSON v
    algebra (FormRadioF _ v) = justJSON v
    algebra (FormArrayF _ v) = justJSON v
    algebra (FormMaybeF _ v) = justJSON v
    algebra (FormTupleF (Just a) (Just b)) = justJSON [a, b]
    algebra (FormTupleF _ _) = Nothing
    algebra (FormObjectF vs) =
        JSON.Object . HashMap.fromList . map (first Text.pack) <$>
        traverse sequence vs
    algebra (FormValueF v) = justJSON v
    algebra (FormSlotRangeF v) = justJSON v
    algebra (FormUnsupportedF _) = Nothing
    justJSON ::
           forall a. ToJSON a
        => a
        -> Maybe JSON.Value
    justJSON = Just . toJSON

------------------------------------------------------------
class ToSchema a where
    toSchema :: FormSchema
    default toSchema :: (Generic a, GenericToSchema (Rep a)) =>
        FormSchema
    toSchema = genericToSchema $ from (undefined :: a)

class ToArgument a where
    toArgument :: a -> Fix FormArgumentF
    default toArgument :: (Generic a, GenericToArgument (Rep a)) =>
        a -> Fix FormArgumentF
    toArgument = genericToArgument . from

instance ToSchema () where
    toSchema = FormSchemaUnit

instance ToArgument () where
    toArgument _ = Fix FormUnitF

instance ToSchema Bool where
    toSchema = FormSchemaBool

instance ToArgument Bool where
    toArgument = Fix . FormBoolF

instance ToSchema Int where
    toSchema = FormSchemaInt

instance ToArgument Int where
    toArgument = Fix . FormIntF . Just

instance ToSchema Integer where
    toSchema = FormSchemaInt

instance ToArgument Integer where
    toArgument = Fix . FormIntF . Just . fromIntegral

instance ToSchema Text where
    toSchema = FormSchemaString

instance ToArgument Text where
    toArgument = Fix . FormStringF . Just . Text.unpack

instance ToSchema a => ToSchema (Proxy a) where
    toSchema = toSchema @a

instance (ToSchema k, ToSchema v) => ToSchema (Data.Map.Map k v) where
    toSchema = FormSchemaArray $ toSchema @(k, v)

instance (ToSchema a, ToSchema b) => ToSchema (a, b) where
    toSchema = FormSchemaTuple (toSchema @a) (toSchema @b)

instance (ToArgument a, ToArgument b) => ToArgument (a, b) where
    toArgument (a, b) = Fix $ FormTupleF (toArgument a) (toArgument b)

instance ToSchema String where
    toSchema = FormSchemaString

instance {-# OVERLAPPABLE #-} (ToSchema a) => ToSchema [a] where
    toSchema = FormSchemaArray (toSchema @a)

instance ToArgument String where
    toArgument = Fix . FormStringF . Just

instance {-# OVERLAPPABLE #-} (ToSchema a, ToArgument a) => ToArgument [a] where
    toArgument xs = Fix $ FormArrayF (toSchema @a) (toArgument <$> xs)

------------------------------------------------------------
class GenericToSchema f where
    genericToSchema :: f a -> FormSchema

instance (GenericToSchema f) => GenericToSchema (D1 d f) where
    genericToSchema (M1 constructors) = genericToSchema constructors

instance (Constructor c, GenericToFields f) => GenericToSchema (C1 c f) where
    genericToSchema c@(M1 selectors) =
        if conIsRecord c
            then FormSchemaObject $ genericToFields selectors
            else FormSchemaUnsupported "Unsupported, non-record constructor."

instance (GenericToConstructorName c1, GenericToConstructorName c2) =>
         GenericToSchema (c1 :+: c2) where
    genericToSchema _ =
        FormSchemaRadio $
        genericToConstructorName (undefined :: c1 a) <>
        genericToConstructorName (undefined :: c2 a)

instance ToSchema a => ToSchema (Maybe a) where
    toSchema = FormSchemaMaybe $ toSchema @a

class GenericToArgument f where
    genericToArgument :: f a -> Fix FormArgumentF

instance (GenericToArgument f) => GenericToArgument (D1 d f) where
    genericToArgument (M1 x) = genericToArgument x

instance (GenericToPairs f, Constructor c) => GenericToArgument (C1 c f) where
    genericToArgument c@(M1 selectors) =
        if conIsRecord c
            then Fix $ FormObjectF $ genericToPairs selectors
            else Fix $ FormUnsupportedF "Unsupported, non-record constructor."

class GenericToPairs f where
    genericToPairs :: f a -> [(String, Fix FormArgumentF)]

instance (GenericToPairs f, GenericToPairs g) => GenericToPairs (f :*: g) where
    genericToPairs (x :*: y) = genericToPairs x <> genericToPairs y

instance (Selector s, ToArgument f) => GenericToPairs (S1 s (Rec0 f)) where
    genericToPairs selector@(M1 (K1 a)) = [(selName selector, toArgument a)]

------------------------------------------------------------
class GenericToConstructorName f where
    genericToConstructorName :: f a -> [String]

instance (Constructor c) => GenericToConstructorName (C1 c U1) where
    genericToConstructorName c = [conName c]

instance (GenericToConstructorName c1, GenericToConstructorName c2) =>
         GenericToConstructorName (c1 :+: c2) where
    genericToConstructorName _ =
        genericToConstructorName (undefined :: c1 a) <>
        genericToConstructorName (undefined :: c2 a)

------------------------------------------------------------
class GenericToFields f where
    genericToFields :: f a -> [(String, FormSchema)]

instance (GenericToFields f, GenericToFields g) =>
         GenericToFields (f :*: g) where
    genericToFields ~(f :*: g) = genericToFields f <> genericToFields g

instance (ToSchema f, Selector s) => GenericToFields (S1 s (Rec0 f)) where
    genericToFields selector = [(selName selector, toSchema @f)]

------------------------------------------------------------
deriveEq1 ''FormArgumentF

deriveShow1 ''FormArgumentF

------------------------------------------------------------
instance ToSchema (Digest SHA256) where
    toSchema = FormSchemaHex

instance ToSchema P.ByteString where
    toSchema = toSchema @String

instance (ToSchema k, ToSchema v) =>
         ToSchema (Language.PlutusTx.AssocMap.Map k v)

instance ToSchema Value where
    toSchema = FormSchemaValue

instance ToArgument Value where
    toArgument = Fix . FormValueF

instance ToSchema LedgerBytes where
    toSchema = toSchema @String

instance ToSchema SlotRange where
    toSchema = FormSchemaSlotRange

deriving anyclass instance ToSchema Ada

deriving anyclass instance ToSchema CurrencySymbol

deriving anyclass instance ToSchema DataScriptHash

deriving anyclass instance ToSchema PubKey

deriving anyclass instance ToSchema RedeemerHash

deriving anyclass instance ToSchema Signature

deriving anyclass instance ToSchema Slot

deriving anyclass instance ToSchema TokenName

deriving anyclass instance ToSchema ValidatorHash

deriving anyclass instance ToSchema Wallet

deriving anyclass instance ToArgument Wallet

deriving anyclass instance ToArgument Ada