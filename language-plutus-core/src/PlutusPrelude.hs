module PlutusPrelude ( (&&&)
                     , toList
                     , bool
                     , first
                     , second
                     , on
                     , fold
                     , (.*)
                     , prettyText
                     , prettyString
                     , throw
                     , Exception
                     , Generic
                     , NFData
                     , Natural
                     , NonEmpty (..)
                     , PairT (..)
                     , Pretty (..)
                     , Typeable
                     , Word8
                     , Semigroup (..)
                     , module X
                     ) where

import           Control.Arrow             (first, second, (&&&))
import           Control.Composition       ((.*))
import           Control.DeepSeq           (NFData)
import           Control.Exception         (Exception, throw)
import           Data.Bool                 (bool)
import           Data.Foldable             (fold, toList)
import           Data.Function             (on)
import           Data.List.NonEmpty        (NonEmpty (..))
import           Data.Semigroup
import           Data.Text                 (Text)
import           Data.Text.Prettyprint.Doc
import           Data.Typeable             (Typeable)
import           Data.Word                 (Word8)
import           Debug.Trace               as X
import           GHC.Generics              (Generic)
import           GHC.Natural               (Natural)

import           Data.Text.Prettyprint.Doc.Render.Text   (renderStrict)
import           Data.Text.Prettyprint.Doc.Render.String (renderString)

newtype PairT b f a = PairT
    { unPairT :: f (b, a)
    }

instance Functor f => Functor (PairT b f) where
    fmap f (PairT p) = PairT $ fmap (fmap f) p
    {-# INLINE fmap #-}

prettyText :: Pretty a => a -> Text
prettyText = renderStrict . layoutPretty defaultLayoutOptions . pretty

prettyString :: Pretty a => a -> String
prettyString = renderString . layoutPretty defaultLayoutOptions . pretty
