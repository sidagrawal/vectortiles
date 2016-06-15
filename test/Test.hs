{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE TypeApplications #-}

module Main where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import           Data.Hex
import           Data.ProtocolBuffers
import           Data.Serialize.Get
import           Data.Serialize.Put
import qualified Geography.VectorTile.Raw as R
import           Test.Tasty
import           Test.Tasty.HUnit
import qualified Text.ProtocolBuffers.WireMessage as PB
import qualified Vector_tile.Tile as VT

---

main :: IO ()
main = do
  op <- BS.readFile "onepoint.mvt"
  ls <- BS.readFile "linestring.mvt"
  pl <- BS.readFile "polygon.mvt"
  rd <- BS.readFile "roads.mvt"
  defaultMain $ suite op ls pl rd
--main = BS.readFile "streets.mvt" >>= defaultMain . suite

{- SUITES -}

suite :: BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString -> TestTree
suite op ls pl rd = testGroup "Unit Tests"
  [ testGroup "Decoding"
    [ testCase "onepoint.mvt -> Raw.Tile" $ testOnePoint op
    , testCase "linestring.mvt -> Raw.Tile" $ testLineString ls
    , testCase "polygon.mvt -> Raw.Tile" $ testPolygon pl
    , testCase "roads.mvt -> Raw.Tile" $ testDecode rd
    ]
  , testGroup "Serialization Isomorphism"
    [ testCase "onepoint.mvt <-> Raw.Tile" $ fromRaw op
    , testCase "linestring.mvt <-> Raw.Tile" $ fromRaw ls
    , testCase "polygon.mvt <-> Raw.Tile" $ fromRaw pl
--    , testCase "roads.mvt <-> Raw.Tile" $ fromRaw rd
    , testCase "testTile <-> protobuf bytes" testTileIso
    ]
  , testGroup "Testing auto-generated code"
    [ testCase "onepoint.mvt <-> VT.Tile" $ pbRawIso op
    , testCase "linestring.mvt <-> VT.Tile" $ pbRawIso ls
    , testCase "polygon.mvt <-> VT.Tile" $ pbRawIso pl
    ]
  , testGroup "Cross-codec Isomorphisms"
    [ testCase "ByteStrings only" crossCodecIso1
    , testCase "Full encode/decode" crossCodecIso
    ]
  ]

testOnePoint :: BS.ByteString -> Assertion
testOnePoint vt = case decodeIt vt of
                    Left e -> assertFailure e
                    Right t -> t @?= onePoint

testLineString :: BS.ByteString -> Assertion
testLineString vt = case decodeIt vt of
                      Left e -> assertFailure e
                      Right t -> t @?= oneLineString

testPolygon :: BS.ByteString -> Assertion
testPolygon vt = case decodeIt vt of
                   Left e -> assertFailure e
                   Right t -> t @?= onePolygon

-- | For testing is decoding succeeded in generally. Makes no guarantee
-- about the quality of the content, only that the parse succeeded.
testDecode :: BS.ByteString -> Assertion
testDecode bs = assert . isRight $ decodeIt bs

fromRaw :: BS.ByteString -> Assertion
fromRaw vt = case decodeIt vt of
               Left e -> assertFailure e
               Right l -> hex (encodeIt l) @?= hex vt
--               Right l -> if runPut (encodeMessage l) == vt
--                          then assert True
--                          else assertString "Isomorphism failed."

testTileIso :: Assertion
testTileIso = case decodeIt pb of
                 Right tl -> assertEqual "" tl testTile
                 Left e -> assertFailure e
  where pb = encodeIt testTile

pbRawIso :: BS.ByteString -> Assertion
pbRawIso vt = case pbIso vt of
                Right vt' -> assertEqual "" (hex vt) (hex vt')
                Left e -> assertFailure e

-- | Can an `R.VectorTile` be converted to a `Vector_tile.Tile` and back?
crossCodecIso :: Assertion
crossCodecIso = case pbIso (encodeIt testTile) >>= decodeIt of
                  Left e -> assertFailure e
                  Right t -> t @?= testTile

-- | Will just their `ByteString` forms match?
crossCodecIso1 :: Assertion
crossCodecIso1 = case pbIso vt of
                  Left e -> assertFailure e
                  Right t -> hex t @?= hex vt
  where vt = encodeIt testTile

-- | Isomorphism for Vector_tile.Tile
pbIso :: BS.ByteString -> Either String BS.ByteString
pbIso (BSL.fromStrict -> vt) = do
   (t,_) <- PB.messageGet @VT.Tile vt
   pure . BSL.toStrict $ PB.messagePut @VT.Tile t

decodeIt :: BS.ByteString -> Either String R.VectorTile
decodeIt = runGet decodeMessage

encodeIt :: R.VectorTile -> BS.ByteString
encodeIt = runPut . encodeMessage

{- UTIL -}

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight _ = False

rawTest :: IO (Either String R.VectorTile)
rawTest = decodeIt <$> BS.readFile "onepoint.mvt"

pbRawTest :: IO (Either String VT.Tile)
pbRawTest = fmap fst . PB.messageGet . BSL.fromStrict <$> BS.readFile "roads.mvt"

testTile :: R.VectorTile
testTile = R.VectorTile $ putField [l]
  where l = R.Layer { R.version = putField 2
                    , R.name = putField "testlayer"
                    , R.features = putField [f]
                    , R.keys = putField ["somekey"]
                    , R.values = putField [v]
                    , R.extent = putField $ Just 4096
                    }
        f = R.Feature { R.featureId = putField $ Just 0
                      , R.tags = putField [0,0]
                      , R.geom = putField $ Just R.Point
                      , R.geometries = putField [9, 50, 34]  -- MoveTo(+25,+17)
                      }
        v = R.Val { R.string = putField $ Just "Some Value"
                  , R.float = putField Nothing
                  , R.double = putField Nothing
                  , R.int64 = putField Nothing
                  , R.uint64 = putField Nothing
                  , R.sint = putField Nothing
                  , R.bool = putField Nothing
                  }

-- | Correct decoding of `onepoint.mvt`
onePoint :: R.VectorTile
onePoint = R.VectorTile $ putField [l]
  where l = R.Layer { R.version = putField 1
                    , R.name = putField "OnePoint"
                    , R.features = putField [f]
                    , R.keys = putField []
                    , R.values = putField []
                    , R.extent = putField $ Just 4096
                    }
        f = R.Feature { R.featureId = putField Nothing
                      , R.tags = putField []
                      , R.geom = putField $ Just R.Point
                      , R.geometries = putField [9, 10, 10]  -- MoveTo(+5,+5)
                      }

-- | Correct decoding of `linestring.mvt`
oneLineString :: R.VectorTile
oneLineString = R.VectorTile $ putField [l]
  where l = R.Layer { R.version = putField 1
                    , R.name = putField "OneLineString"
                    , R.features = putField [f]
                    , R.keys = putField []
                    , R.values = putField []
                    , R.extent = putField $ Just 4096
                    }
        f = R.Feature { R.featureId = putField Nothing
                      , R.tags = putField []
                      , R.geom = putField $ Just R.LineString
                      -- MoveTo(+5,+5), LineTo(+1195,+1195)
                      , R.geometries = putField [9, 10, 10, 10, 2390, 2390]
                      }

-- | Correct decoding of `polygon.mvt`
onePolygon :: R.VectorTile
onePolygon = R.VectorTile $ putField [l]
  where l = R.Layer { R.version = putField 1
                    , R.name = putField "OnePolygon"
                    , R.features = putField [f]
                    , R.keys = putField []
                    , R.values = putField []
                    , R.extent = putField $ Just 4096
                    }
        f = R.Feature { R.featureId = putField Nothing
                      , R.tags = putField []
                      , R.geom = putField $ Just R.Polygon
                      -- MoveTo(+2,+2), LineTo(+3,+2), LineTo(-3,+2), ClosePath
                      , R.geometries = putField [9, 4, 4, 18, 6, 4, 5, 4, 15]
                      }
