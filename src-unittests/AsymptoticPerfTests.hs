{-# LANGUAGE QuasiQuotes #-}

module AsymptoticPerfTests
  ( asymptoticPerfTest
  )
where



#include "prelude.inc"

import Test.Hspec

import NeatInterpolation

import Language.Haskell.Brittany

import TestUtils



asymptoticPerfTest :: Spec
asymptoticPerfTest = do
  it "1000 do statements"
    $  roundTripEqualWithTimeout 1000000
    $  (Text.pack "func = do\n")
    <> Text.replicate 1000 (Text.pack "  statement\n")
  it "1000 do nestings"
    $  roundTripEqualWithTimeout 4000000
    $  (Text.pack "func = ")
    <> mconcat
         (   [0 .. 999]
         <&> \(i :: Int) ->
               (Text.replicate (2 * i) (Text.pack " ") <> Text.pack "do\n")
         )
    <> Text.replicate 2000 (Text.pack " ")
    <> Text.pack "return\n"
    <> Text.replicate 2002 (Text.pack " ")
    <> Text.pack "()"
  it "1000 AppOps"
    $  roundTripEqualWithTimeout 1000000
    $  (Text.pack "func = expr")
    <> Text.replicate 200 (Text.pack "\n     . expr") --TODO
