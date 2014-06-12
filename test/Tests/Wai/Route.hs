-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators     #-}

module Tests.Wai.Route (tests) where

import Data.ByteString (ByteString)
import Data.Monoid
import Data.String
import Network.HTTP.Types
import Network.Wai
import Network.Wai.Predicate
import Network.Wai.Predicate.Request
import Network.Wai.Routing
import Network.Wai.Routing.Request
import Test.HUnit hiding (Test)
import Test.Tasty
import Test.Tasty.HUnit
import Tests.Wai.Util

import qualified Data.ByteString.Lazy as Lazy

type App m = Request -> m Response

tests :: TestTree
tests = testGroup "Network.Wai.Routing"
    [ testCase "Sitemap" testSitemap
    , testCase "Media Selection" testMedia
    ]

testSitemap :: IO ()
testSitemap = do
    let routes = prepare sitemap

    [7,6,5,4,3,2,1,0] @=? map routeMeta (examine sitemap)
    ["/a", "/b", "/c", "/d", "/e", "/f", "/g", "/h"] @=? map fst routes

    let handler = route routes
    testEndpointA handler
    testEndpointB handler
    testEndpointC handler
    testEndpointD handler
    testEndpointE handler
    testEndpointF handler
    testEndpointH handler

sitemap :: Routes Int IO ()
sitemap = do
    get "/a" handlerA $
        accept "application" "json" .&. (query "name" .|. query "nick") .&. query "foo"

    attach 0

    get "/b" handlerB $
        query "baz"

    attach 1

    get "/c" handlerC $
        opt (query "foo")

    attach 2

    get "/d" handlerD $
        def 0 (query "foo")

    attach 3

    get "/e" handlerE $
        def 0 (header "foo")

    attach 4

    get "/f" handlerF $
        query "foo"

    attach 5

    get "/g" handlerG true

    attach 6

    get "/h" handlerH $
        cookie "user" .&. cookie "age"

    attach 7

handlerA :: Media "application" "json" ::: Int ::: ByteString -> IO Response
handlerA (_ ::: i ::: _) = writeText (fromString . show $ i)

handlerB :: Int -> IO Response
handlerB baz = writeText (fromString . show $ baz)

handlerC :: Maybe Int -> IO Response
handlerC foo = writeText (fromString . show $ foo)

handlerD :: Int -> IO Response
handlerD foo = writeText (fromString . show $ foo)

handlerE :: Int -> IO Response
handlerE foo = writeText (fromString . show $ foo)

handlerF :: [Int] -> IO Response
handlerF foo = writeText (fromString . show . sum $ foo)

handlerG :: () -> IO Response
handlerG = const $ writeText "all good"

handlerH :: Lazy.ByteString ::: Int -> IO Response
handlerH (user ::: age) = writeText $
    "user = " <> user <> ", age = " <> fromString (show age)

testEndpointA :: App IO -> Assertion
testEndpointA f = do
    let rq = defaultRequest { rawPathInfo = "/a" }

    rs0 <- f $ withHeader "Accept" "foo/bar" rq
    status406 @=? responseStatus rs0

    rs1 <- f $ json rq
    status400 @=? responseStatus rs1

    rs2 <- f . json . withQuery "name" "x" $ rq
    status400 @=? responseStatus rs2

    rs3 <- f . json . withQuery "name" "123" . withQuery "foo" "\"z\"" $ rq
    status200 @=? responseStatus rs3


testEndpointB :: App IO -> Assertion
testEndpointB f = do
    let rq = defaultRequest { rawPathInfo = "/b" }

    rs0 <- f rq
    status400 @=? responseStatus rs0
    "'baz' not-available [query]" @=? responseBody rs0

    rs1 <- f . withQuery "baz" "abc" $ rq
    status400 @=? responseStatus rs1
    "'baz' type-error [query] -- Failed reading: Invalid Int" @=? responseBody rs1

    rs2 <- f . withQuery "baz" "abc" . withQuery "baz" "123" $ rq
    status200 @=? responseStatus rs2
    "123" @=? responseBody rs2


testEndpointC :: App IO -> Assertion
testEndpointC f = do
    let rq = defaultRequest { rawPathInfo = "/c" }

    rs0 <- f rq
    status200 @=? responseStatus rs0
    "Nothing" @=? responseBody rs0

    rs1 <- f . withQuery "foo" "abc" . withQuery "foo" "123" $ rq
    status200  @=? responseStatus rs1
    "Just 123" @=? responseBody rs1

    rs2 <- f . withQuery "foo" "abc" $ rq
    status400 @=? responseStatus rs2
    "'foo' type-error [query] -- Failed reading: Invalid Int" @=? responseBody rs2


testEndpointD :: App IO -> Assertion
testEndpointD f = do
    let rq = defaultRequest { rawPathInfo = "/d" }

    rs0 <- f rq
    status200 @=? responseStatus rs0
    "0"       @=? responseBody rs0

    rs1 <- f . withQuery "foo" "xxx" . withQuery "foo" "42" $ rq
    status200 @=? responseStatus rs1
    "42"      @=? responseBody rs1

    rs2 <- f . withQuery "foo" "yyy" $ rq
    status400 @=? responseStatus rs2
    "'foo' type-error [query] -- Failed reading: Invalid Int" @=? responseBody rs2


testEndpointE :: App IO -> Assertion
testEndpointE f = do
    let rq = defaultRequest { rawPathInfo = "/e" }

    rs0 <- f rq
    status200 @=? responseStatus rs0
    "0"       @=? responseBody rs0

    rs1 <- f $ withHeader "foo" "42" rq
    status200 @=? responseStatus rs1
    "42"      @=? responseBody rs1

    rs2 <- f $ withHeader "foo" "abc" rq
    status400 @=? responseStatus rs2
    "'foo' type-error [header] -- Failed reading: Invalid Int" @=? responseBody rs2


testEndpointF :: App IO -> Assertion
testEndpointF f = do
    let rq = defaultRequest { rawPathInfo = "/f" }

    rs0 <- f . withQuery "foo" "1,2,3,4" $ rq
    status200 @=? responseStatus rs0
    "10"      @=? responseBody rs0


testEndpointH :: App IO -> Assertion
testEndpointH f = do
    let rq = defaultRequest { rawPathInfo = "/h" }

    rs0 <- f rq
    status400 @=? responseStatus rs0
    "'user' not-available [cookie]" @=? responseBody rs0

    rs1 <- f . withHeader "Cookie" "user=joe" $ rq
    status400 @=? responseStatus rs1
    "'age' not-available [cookie]" @=? responseBody rs1

    rs2 <- f . withHeader "Cookie" "user=joe; age=42" $ rq
    status200 @=? responseStatus rs2
    "user = joe, age = 42" @=? responseBody rs2

-----------------------------------------------------------------------------
-- Media Selection Tests

testMedia :: IO ()
testMedia = do
    let [(_, h)] = prepare sitemapMedia
    expectMedia "application/json;q=0.3, application/x-thrift;q=0.7" "application/x-thrift" h
    expectMedia "application/json;q=0.7, application/x-thrift;q=0.3" "application/json" h

sitemapMedia :: Routes a IO ()
sitemapMedia = do
    get "/media" handlerJson   $ accept "application" "json"
    get "/media" handlerThrift $ accept "application" "x-thrift"

handlerJson :: Media "application" "json" -> IO Response
handlerJson _ = writeText "application/json"

handlerThrift :: Media "application" "x-thrift" -> IO Response
handlerThrift _ = writeText "application/x-thrift"

expectMedia :: ByteString -> ByteString -> (RoutingReq -> IO Response) -> Assertion
expectMedia h res m = do
    let rq = defaultRequest { rawPathInfo = "/media" }
    rs <- m . fromReq [] . fromRequest . withHeader "Accept" h $ rq
    Lazy.fromStrict res @=? responseBody rs
