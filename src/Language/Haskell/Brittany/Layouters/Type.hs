{-# LANGUAGE DataKinds #-}

module Language.Haskell.Brittany.Layouters.Type
  ( layoutType
  )
where



#include "prelude.inc"

import           Language.Haskell.Brittany.Config.Types
import           Language.Haskell.Brittany.Types
import           Language.Haskell.Brittany.LayouterBasics

import           RdrName ( RdrName(..) )
import           GHC ( runGhc, GenLocated(L), moduleNameString )
import           Language.Haskell.GHC.ExactPrint.Types ( mkAnnKey )
import           HsSyn
import           Name
import           Outputable ( ftext, showSDocUnsafe )

import           DataTreePrint



layoutType :: ToBriDoc HsType
layoutType ltype@(L _ typ) = docWrapNode ltype $ case typ of
  -- _ | traceShow (ExactPrint.Types.mkAnnKey ltype) False -> error "impossible"
  HsTyVar name -> do
    t <- lrdrNameToTextAnn name
    docWrapNode name $ docLit t
  HsForAllTy bndrs (L _ (HsQualTy (L _ cntxts@(_:_)) typ2)) -> do
    typeDoc <- docSharedWrapper layoutType typ2
    tyVarDocs <- bndrs `forM` \case
      (L _ (UserTyVar name)) -> return $ (lrdrNameToText name, Nothing)
      (L _ (KindedTyVar lrdrName kind)) -> do
        d <- docSharedWrapper layoutType kind
        return $ (lrdrNameToText lrdrName, Just $ d)
    cntxtDocs <- cntxts `forM` docSharedWrapper layoutType
    let maybeForceML = case typ2 of
          (L _ HsFunTy{}) -> docForceMultiline
          _               -> id
    let
      tyVarDocLineList = tyVarDocs >>= \case
        (tname, Nothing) -> [docLit $ Text.pack " " <> tname]
        (tname, Just doc) -> [ docLit $ Text.pack " ("
                                    <> tname
                                    <> Text.pack " :: "
                             , docForceSingleline $ doc
                             , docLit $ Text.pack ")"
                             ]
      forallDoc = docAlt
        [ let
            open = docLit $ Text.pack "forall"
            in docSeq ([open]++tyVarDocLineList)
        , docPar
            (docLit (Text.pack "forall"))
            (docLines
            $ tyVarDocs <&> \case
                (tname, Nothing) -> docEnsureIndent BrIndentRegular $ docLit tname
                (tname, Just doc) -> docEnsureIndent BrIndentRegular
                  $ docLines
                    [ docCols ColTyOpPrefix
                      [ docParenLSep
                      , docLit tname
                      ]
                    , docCols ColTyOpPrefix
                      [ docLit $ Text.pack ":: "
                      , doc
                      ]
                    , docLit $ Text.pack ")"
                    ])
        ]
      contextDoc = case cntxtDocs of
        [x] -> x
        _ -> docAlt
          [ let
              open  = docLit $ Text.pack "("
              close = docLit $ Text.pack ")"
              list  = List.intersperse docCommaSep
                    $ docForceSingleline <$> cntxtDocs
              in docSeq ([open]++list++[close])
          , let
              open = docCols ColTyOpPrefix
                      [ docParenLSep
                      , docAddBaseY (BrIndentSpecial 2) $ head cntxtDocs
                      ]
              close = docLit $ Text.pack ")"
              list = List.tail cntxtDocs <&> \cntxtDoc ->
                     docCols ColTyOpPrefix
                      [ docCommaSep
                      , docAddBaseY (BrIndentSpecial 2) cntxtDoc
                      ]
            in docPar open $ docLines $ list ++ [close]
          ]
    docAlt
      -- :: forall a b c . (Foo a b c) => a b -> c
      [ docSeq
        [ if null bndrs
            then docEmpty
            else let
              open = docLit $ Text.pack "forall"
              close = docLit $ Text.pack " . "
              in docSeq ([open]++tyVarDocLineList++[close])
        , docForceSingleline contextDoc
        , docLit $ Text.pack " => "
        , typeDoc
        ]
      -- :: forall a b c
      --  . (Foo a b c)
      -- => a b
      -- -> c
      , docPar
          forallDoc
          ( docLines
            [ docCols ColTyOpPrefix
              [ docWrapNodeRest ltype $ docLit $ Text.pack " . "
              , docAddBaseY (BrIndentSpecial 3)
              $ docForceSingleline contextDoc
              ]
            , docCols ColTyOpPrefix
              [ docLit $ Text.pack "=> "
              , docAddBaseY (BrIndentSpecial 3) $ maybeForceML $ typeDoc
              ]
            ]
          )
      ]
  HsForAllTy bndrs typ2 -> do
    typeDoc <- layoutType typ2
    tyVarDocs <- bndrs `forM` \case
      (L _ (UserTyVar name)) -> return $ (lrdrNameToText name, Nothing)
      (L _ (KindedTyVar lrdrName kind)) -> do
        d <- layoutType kind
        return $ (lrdrNameToText lrdrName, Just $ return d)
    let
      tyVarDocLineList = tyVarDocs >>= \case
        (tname, Nothing) -> [docLit $ Text.pack " " <> tname]
        (tname, Just doc) -> [ docLit $ Text.pack " ("
                                    <> tname
                                    <> Text.pack " :: "
                             , docForceSingleline doc
                             , docLit $ Text.pack ")"
                             ]
    docAlt
      [ docSeq
        [ if null bndrs
            then docEmpty
            else let
              open = docLit $ Text.pack "forall"
              close = docLit $ Text.pack " . "
              in docSeq ([open]++tyVarDocLineList++[close])
        , return typeDoc
        ]
      , docPar
          (docSeq $ docLit (Text.pack "forall") : tyVarDocLineList)
          ( docCols ColTyOpPrefix
            [ docWrapNodeRest ltype $ docLit $ Text.pack ". "
            , return typeDoc
            ]
          )
      , docPar
          (docLit (Text.pack "forall"))
          (docLines
          $ (tyVarDocs <&> \case
              (tname, Nothing) -> docEnsureIndent BrIndentRegular $ docLit tname
              (tname, Just doc) -> docEnsureIndent BrIndentRegular
                $ docLines
                  [ docCols ColTyOpPrefix
                    [ docParenLSep
                    , docLit tname
                    ]
                  , docCols ColTyOpPrefix
                    [ docLit $ Text.pack ":: "
                    , doc
                    ]
                  , docLit $ Text.pack ")"
                  ]
            )
          ++[ docCols ColTyOpPrefix
              [ docWrapNodeRest ltype $ docLit $ Text.pack ". "
              , return typeDoc
              ]
            ]
          )
      ]
  (HsQualTy (L _ []) _) ->
    briDocByExactInlineOnly "HsQualTy [] _" ltype
  HsQualTy lcntxts@(L _ cntxts@(_:_)) typ1 -> do
    typeDoc <- docSharedWrapper layoutType typ1
    cntxtDocs <- cntxts `forM` docSharedWrapper layoutType
    let
      contextDoc = docWrapNode lcntxts $ case cntxtDocs of
        [x] -> x
        _ -> docAlt
          [ let
              open  = docLit $ Text.pack "("
              close = docLit $ Text.pack ")"
              list  = List.intersperse docCommaSep
                    $ docForceSingleline <$> cntxtDocs
              in docSeq ([open]++list++[close])
          , let
              open = docCols ColTyOpPrefix
                      [ docParenLSep
                      , docAddBaseY (BrIndentSpecial 2)
                      $ head cntxtDocs
                      ]
              close = docLit $ Text.pack ")"
              list = List.tail cntxtDocs <&> \cntxtDoc ->
                     docCols ColTyOpPrefix
                      [ docCommaSep
                      , docAddBaseY (BrIndentSpecial 2) 
                      $ cntxtDoc
                      ]
            in docPar open $ docLines $ list ++ [close]
          ]
    let maybeForceML = case typ1 of
          (L _ HsFunTy{}) -> docForceMultiline
          _               -> id
    docAlt
      -- (Foo a b c) => a b -> c
      [ docSeq
        [ docForceSingleline contextDoc
        , docLit $ Text.pack " => "
        , docForceSingleline typeDoc
        ]
      --    (Foo a b c)
      -- => a b
      -- -> c
      , docPar
          (docForceSingleline contextDoc)
          ( docCols ColTyOpPrefix
            [ docLit $ Text.pack "=> "
            , docAddBaseY (BrIndentSpecial 3) $ maybeForceML typeDoc
            ]
          )
      ]
  HsFunTy typ1 typ2 -> do
    typeDoc1 <- docSharedWrapper layoutType typ1
    typeDoc2 <- docSharedWrapper layoutType typ2
    let maybeForceML = case typ2 of
          (L _ HsFunTy{}) -> docForceMultiline
          _               -> id
    hasComments <- hasAnyCommentsBelow ltype
    docAlt $
      [ docSeq
        [ appSep $ docForceSingleline typeDoc1
        , appSep $ docLit $ Text.pack "->"
        , docForceSingleline typeDoc2
        ]
      | not hasComments
      ] ++
      [ docPar
        (docNodeAnnKW ltype Nothing typeDoc1)
        ( docCols ColTyOpPrefix
          [ docWrapNodeRest ltype $ appSep $ docLit $ Text.pack "->"
          , docAddBaseY (BrIndentSpecial 3)
          $ maybeForceML typeDoc2
          ]
        )
      ]
  HsParTy typ1 -> do
    typeDoc1 <- docSharedWrapper layoutType typ1
    docAlt
      [ docSeq
        [ docWrapNodeRest ltype $ docLit $ Text.pack "("
        , docForceSingleline typeDoc1
        , docLit $ Text.pack ")"
        ]
      , docPar
          ( docCols ColTyOpPrefix
            [ docWrapNodeRest ltype $ docParenLSep
            , docAddBaseY (BrIndentSpecial 2) $ typeDoc1
            ])
          (docLit $ Text.pack ")")
      ]
  HsAppTy typ1 typ2 -> do
    typeDoc1 <- docSharedWrapper layoutType typ1
    typeDoc2 <- docSharedWrapper layoutType typ2
    docAlt
      [ docSeq
        [ docForceSingleline typeDoc1
        , docLit $ Text.pack " "
        , docForceSingleline typeDoc2
        ]
      , docPar
          typeDoc1
          (docEnsureIndent BrIndentRegular typeDoc2)
      ]
  HsAppsTy [] -> error "HsAppsTy []"
  HsAppsTy [L _ (HsAppPrefix typ1)] -> do
    typeDoc1 <- docSharedWrapper layoutType typ1
    typeDoc1
  HsAppsTy [_lname@(L _ (HsAppInfix name))] -> do
    -- this redirection is somewhat hacky, but whatever.
    -- TODO: a general problem when doing deep inspections on
    --       the type (and this is not the only instance)
    --       is that we potentially omit annotations on some of
    --       the middle constructors. i have no idea under which
    --       circumstances exactly important annotations (comments)
    --       would be assigned to such constructors.
    typeDoc1 <- -- docSharedWrapper layoutType $ (L l $ HsTyVar name)
      lrdrNameToTextAnnTypeEqualityIsSpecial name
    docLit typeDoc1
  HsAppsTy (L _ (HsAppPrefix typHead):typRestA)
    | Just typRest <- mapM (\case L _ (HsAppPrefix t) -> Just t
                                  _ -> Nothing) typRestA -> do
    docHead <- docSharedWrapper layoutType typHead
    docRest <- docSharedWrapper layoutType `mapM` typRest
    docAlt
      [ docSeq
      $ docForceSingleline docHead : (docRest >>= \d ->
        [ docLit $ Text.pack " ", docForceSingleline d ])
      , docPar docHead (docLines $ docEnsureIndent BrIndentRegular <$> docRest)
      ]
  HsAppsTy (typHead:typRest) -> do
    docHead <- docSharedWrapper layoutAppType typHead
    docRest <- docSharedWrapper layoutAppType `mapM` typRest
    docAlt
      [ docSeq
      $ docForceSingleline docHead : (docRest >>= \d ->
        [ docLit $ Text.pack " ", docForceSingleline d ])
      , docPar docHead (docLines $ docEnsureIndent BrIndentRegular <$> docRest)
      ]
    where
      layoutAppType (L _ (HsAppPrefix t)) = layoutType t
      layoutAppType (L _ (HsAppInfix t))  = docLit =<< lrdrNameToTextAnnTypeEqualityIsSpecial t
  HsListTy typ1 -> do
    typeDoc1 <- docSharedWrapper layoutType typ1
    docAlt
      [ docSeq
        [ docWrapNodeRest ltype $ docLit $ Text.pack "["
        , docForceSingleline typeDoc1
        , docLit $ Text.pack "]"
        ]
      , docPar
          ( docCols ColTyOpPrefix
            [ docWrapNodeRest ltype $ docLit $ Text.pack "[ "
            , docAddBaseY (BrIndentSpecial 2) $ typeDoc1
            ])
          (docLit $ Text.pack "]")
      ]
  HsPArrTy typ1 -> do
    typeDoc1 <- docSharedWrapper layoutType typ1
    docAlt
      [ docSeq
        [ docWrapNodeRest ltype $ docLit $ Text.pack "[:"
        , docForceSingleline typeDoc1
        , docLit $ Text.pack ":]"
        ]
      , docPar
          ( docCols ColTyOpPrefix
            [ docWrapNodeRest ltype $ docLit $ Text.pack "[:"
            , docAddBaseY (BrIndentSpecial 2) $ typeDoc1
            ])
          (docLit $ Text.pack ":]")
      ]
  HsTupleTy tupleSort typs -> case tupleSort of
    HsUnboxedTuple           -> unboxed
    HsBoxedTuple             -> simple
    HsConstraintTuple        -> simple
    HsBoxedOrConstraintTuple -> simple
   where
    unboxed = if null typs then error "unboxed unit?" else unboxedL
    simple = if null typs then unitL else simpleL
    unitL = docLit $ Text.pack "()"
    simpleL = do
      docs <- docSharedWrapper layoutType `mapM` typs
      docAlt
        [ docSeq $ [docLit $ Text.pack "("]
               ++ List.intersperse docCommaSep (docForceSingleline <$> docs)
               ++ [docLit $ Text.pack ")"]
        , let
            start = docCols ColTyOpPrefix [docParenLSep, head docs]
            lines = List.tail docs <&> \d ->
                    docCols ColTyOpPrefix [docCommaSep, d]
            end   = docLit $ Text.pack ")"
          in docPar
            (docAddBaseY (BrIndentSpecial 2) $ start)
            (docLines $ (docAddBaseY (BrIndentSpecial 2) <$> lines) ++ [end])
        ]
    unboxedL = do
      docs <- docSharedWrapper layoutType `mapM` typs
      docAlt
        [ docSeq $ [docLit $ Text.pack "(#"]
               ++ List.intersperse docCommaSep docs
               ++ [docLit $ Text.pack "#)"]
        , let
            start = docCols ColTyOpPrefix [docLit $ Text.pack "(#", head docs]
            lines = List.tail docs <&> \d ->
                    docCols ColTyOpPrefix [docCommaSep, d]
            end   = docLit $ Text.pack "#)"
          in docPar
            (docAddBaseY (BrIndentSpecial 2) start)
            (docLines $ (docAddBaseY (BrIndentSpecial 2) <$> lines) ++ [end])
        ]
  HsOpTy{} -> -- TODO
    briDocByExactInlineOnly "HsOpTy{}" ltype
  -- HsOpTy typ1 opName typ2 -> do
  --   -- TODO: these need some proper fixing. precedences don't add up.
  --   --       maybe the parser just returns some trivial right recursion
  --   --       parse result for any type level operators.
  --   --       need to check how things are handled on the expression level.
  --   let opStr = lrdrNameToText opName
  --   let opLen = Text.length opStr
  --   layouter1@(Layouter desc1 _ _) <- layoutType typ1
  --   layouter2@(Layouter desc2 _ _) <- layoutType typ2
  --   let line = do -- Maybe
  --         l1 <- _ldesc_line desc1
  --         l2 <- _ldesc_line desc2
  --         let len1 = _lColumns_min l1
  --         let len2 = _lColumns_min l2
  --         let len = 2 + opLen + len1 + len2
  --         return $ LayoutColumns
  --           { _lColumns_key = ColumnKeyUnique
  --           , _lColumns_lengths = [len]
  --           , _lColumns_min = len
  --           }
  --   let block = do -- Maybe
  --         rol1 <- descToBlockStart desc1
  --         (min2, max2) <- descToMinMax (1+opLen) desc2
  --         let (minR, maxR) = case descToBlockMinMax desc1 of
  --               Nothing -> (min2, max2)
  --               Just (min1, max1) -> (max min1 min2, max max1 max2)
  --         return $ BlockDesc
  --           { _bdesc_blockStart = rol1
  --           , _bdesc_min = minR
  --           , _bdesc_max = maxR
  --           , _bdesc_opIndentFloatUp = Just (1+opLen)
  --           }
  --   return $ Layouter
  --     { _layouter_desc = LayoutDesc
  --       { _ldesc_line = line
  --       , _ldesc_block = block
  --       }
  --     , _layouter_func = \params -> do
  --         remaining <- getCurRemaining
  --         let allowSameLine = _params_sepLines params /= SepLineTypeOp
  --         case line of
  --           Just (LayoutColumns _ _ m) | m <= remaining && allowSameLine -> do
  --             applyLayouterRestore layouter1 defaultParams
  --             layoutWriteAppend $ Text.pack " " <> opStr <> Text.pack " "
  --             applyLayouterRestore layouter2 defaultParams
  --           _ -> do
  --             let upIndent   = maybe (1+opLen) (max (1+opLen)) $ _params_opIndent params
  --             let downIndent = maybe upIndent (max upIndent) $ _bdesc_opIndentFloatUp =<< _ldesc_block desc2
  --             layoutWithAddIndentN downIndent $ applyLayouterRestore layouter1 defaultParams
  --             layoutWriteNewline
  --             layoutWriteAppend $ opStr <> Text.pack " "
  --             layoutWriteEnsureBlockPlusN downIndent
  --             applyLayouterRestore layouter2 defaultParams
  --               { _params_sepLines = SepLineTypeOp
  --               , _params_opIndent = Just downIndent
  --               }
  --     , _layouter_ast = ltype
  --     }
  HsIParamTy (HsIPName ipName) typ1 -> do
    typeDoc1 <- docSharedWrapper layoutType typ1
    docAlt
      [ docSeq
        [ docWrapNodeRest ltype
        $ docLit
        $ Text.pack ("?" ++ showSDocUnsafe (ftext ipName) ++ "::")
        , docForceSingleline typeDoc1
        ]
      , docPar
          ( docLit
          $ Text.pack ("?" ++ showSDocUnsafe (ftext ipName))
          )
          (docCols ColTyOpPrefix
            [ docWrapNodeRest ltype
            $ docLit $ Text.pack "::"
            , docAddBaseY (BrIndentSpecial 2) typeDoc1
            ])
      ]
  HsEqTy typ1 typ2 -> do
    typeDoc1 <- docSharedWrapper layoutType typ1
    typeDoc2 <- docSharedWrapper layoutType typ2
    docAlt
      [ docSeq
        [ docForceSingleline typeDoc1
        , docWrapNodeRest ltype
        $ docLit $ Text.pack " ~ "
        , docForceSingleline typeDoc2
        ]
      , docPar
          typeDoc1
          ( docCols ColTyOpPrefix
              [ docWrapNodeRest ltype
              $ docLit $ Text.pack "~ "
              , docAddBaseY (BrIndentSpecial 2) typeDoc2
              ])
      ]
  -- TODO: test KindSig
  HsKindSig typ1 kind1 -> do
    typeDoc1 <- docSharedWrapper layoutType typ1
    kindDoc1 <- docSharedWrapper layoutType kind1
    docAlt
      [ docSeq
        [ docForceSingleline typeDoc1
        , docLit $ Text.pack " :: "
        , docForceSingleline kindDoc1
        ]
      , docPar
          typeDoc1
          ( docCols ColTyOpPrefix
              [ docWrapNodeRest ltype
              $ docLit $ Text.pack ":: "
              , docAddBaseY (BrIndentSpecial 3) kindDoc1
              ])
      ]
  HsBangTy{} -> -- TODO
    briDocByExactInlineOnly "HsBangTy{}" ltype
  -- HsBangTy bang typ1 -> do
  --   let bangStr = case bang of
  --         HsSrcBang _ unpackness strictness ->
  --           (++)
  --             (case unpackness of
  --               SrcUnpack   -> "{-# UNPACK -#} "
  --               SrcNoUnpack -> "{-# NOUNPACK -#} "
  --               NoSrcUnpack -> ""
  --             )
  --             (case strictness of
  --               SrcLazy     -> "~"
  --               SrcStrict   -> "!"
  --               NoSrcStrict -> ""
  --             )
  --   let bangLen = length bangStr
  --   layouter@(Layouter desc _ _) <- layoutType typ1
  --   let line = do -- Maybe
  --         l <- _ldesc_line desc
  --         let len = bangLen + _lColumns_min l
  --         return $ LayoutColumns
  --           { _lColumns_key = ColumnKeyUnique
  --           , _lColumns_lengths = [len]
  --           , _lColumns_min = len
  --           }
  --   let block = do -- Maybe
  --         rol <- descToBlockStart desc
  --         (minR,maxR) <- descToBlockMinMax desc
  --         return $ BlockDesc
  --           { _bdesc_blockStart = rol
  --           , _bdesc_min = minR
  --           , _bdesc_max = maxR
  --           , _bdesc_opIndentFloatUp = Nothing
  --           }
  --   return $ Layouter
  --     { _layouter_desc = LayoutDesc
  --       { _ldesc_line = line
  --       , _ldesc_block = block
  --       }
  --     , _layouter_func = \_params -> do
  --         remaining <- getCurRemaining
  --         case line of
  --           Just (LayoutColumns _ _ m) | m <= remaining -> do
  --             layoutWriteAppend $ Text.pack $ bangStr
  --             applyLayouterRestore layouter defaultParams
  --           _ -> do
  --             layoutWriteAppend $ Text.pack $ bangStr
  --             layoutWritePostCommentsRestore ltype
  --             applyLayouterRestore layouter defaultParams
  --     , _layouter_ast = ltype
  --     }
  HsSpliceTy{} -> -- TODO
    briDocByExactInlineOnly "" ltype
  HsDocTy{} -> -- TODO
    briDocByExactInlineOnly "" ltype
  HsRecTy{} -> -- TODO
    briDocByExactInlineOnly "" ltype
  HsExplicitListTy _ typs -> do
    typDocs <- docSharedWrapper layoutType `mapM` typs
    docAlt
      [ docSeq
      $  [docLit $ Text.pack "'["]
      ++ List.intersperse docCommaSep typDocs
      ++ [docLit $ Text.pack "]"]
      -- TODO
      ]
  HsExplicitTupleTy{} -> -- TODO
    briDocByExactInlineOnly "" ltype
  HsTyLit{} -> -- TODO
    briDocByExactInlineOnly "" ltype
  HsCoreTy{} -> -- TODO
    briDocByExactInlineOnly "" ltype
  HsWildCardTy _ ->
    docLit $ Text.pack "_"
