module Csound.Render.Pretty (
    Doc, int, double, text, empty, ($$), vcat, vcatMap,
    verbatimLines,

    binaries, unaries, funcs,
    binary, unary, func,
    ppMapTable,
    ppStmt,
    ($=), ppOpc, ppProc, ppVar,
    ppPrim, ppTab, ppStrget, ppStrset, ppTabDef, ppConvertRate, ppIf,
    ppCsdFile, ppInstr, ppInstr0, ppScore, ppNote, ppTotalDur, ppOrc, ppSco, 
    ppInline, ppCondOp, ppNumOp,
    ppEvent, ppMasterNote, ppAlwayson
) where

import Data.Char(toLower)
import qualified Data.Map as M
import qualified Data.IntMap as IM
import Text.PrettyPrint.Leijen

import Csound.Tfm.Tab
import Csound.Exp 

vcatMap :: (a -> Doc) -> [a] -> Doc
vcatMap f = vcat . fmap f

verbatimLines :: [String] -> Doc
verbatimLines = vcat . fmap text

($$) = (<$$>)

binaries, unaries, funcs :: String -> [Doc] -> Doc

binaries op as = binary op (as !! 0) (as !! 1)
unaries  op as = unary  op (as !! 0)
funcs    op as = func   op (as !! 0)

binary :: String -> Doc -> Doc -> Doc
binary op a b = parens $ a <+> text op <+> b

unary :: String -> Doc -> Doc
unary op a = parens $ text op <> a

func :: String -> Doc -> Doc
func op a = text op <> parens a

ppMapTable :: (a -> Int -> Doc) -> Index a -> Doc
ppMapTable phi = vcat . map (uncurry phi) . M.toList . indexElems


ppRate :: Rate -> Doc
ppRate x = case x of
    Sr -> char 'S'
    _  -> phi x
    where phi = text . map toLower . show 

ppPrimOrVar :: PrimOr RatedVar -> Doc
ppPrimOrVar x = either ppPrim ppRatedVar $ unPrimOr x

ppRatedVar :: RatedVar -> Doc
ppRatedVar v = ppRate (ratedVarRate v) <> int (ratedVarId v)

ppOuts :: [RatedVar] -> Doc
ppOuts xs = hsep $ punctuate comma $ map ppRatedVar xs

($=) :: Doc -> Doc -> Doc
($=) a b = a <+> equals <+> b

ppOpc :: Doc -> String -> [Doc] -> Doc
ppOpc out name xs = out <+> ppProc name xs

ppProc :: String -> [Doc] -> Doc
ppProc name xs = text name <+> (hsep $ punctuate comma xs)

ppVar :: Var -> Doc
ppVar v = case v of
    Var ty rate name -> ppVarType ty <> ppRate rate <> text name
    VarVerbatim _ name -> text name

ppVarType :: VarType -> Doc
ppVarType x = case x of
    LocalVar -> empty
    GlobalVar -> char 'g'

ppPrim :: Prim -> Doc
ppPrim x = case x of
    P n -> char 'p' <> int n
    PrimInt n -> int n
    PrimDouble d -> double d
    PrimString s -> dquotes $ text s
    PrimTab f -> error $ "i'm lost table, please substitute me (" ++ (show f) ++ ")" 
    
ppTab :: LowTab -> Doc
ppTab (LowTab size n xs) = text "gen" <> int n <+> int size <+> (hsep $ map double xs)
 
ppIf :: Doc -> Doc -> Doc -> Doc
ppIf p t e = p <+> char '?' <+> t <+> char ':' <+> e

ppStrget :: Doc -> Int -> Doc
ppStrget out n = ppOpc out "strget" [char 'p' <> int n]

ppConvertRate :: Doc -> Rate -> Rate -> Doc -> Doc
ppConvertRate out to from var = case (to, from) of
    (Ar, Kr) -> upsamp var 
    (Ar, Ir) -> upsamp $ k var
    (Kr, Ar) -> downsamp var
    (Kr, Ir) -> out $= k var
    (Ir, Ar) -> downsamp var
    (Ir, Kr) -> out $= i var
    where upsamp x = ppOpc out "upsamp" [x]
          downsamp x = ppOpc out "downsamp" [x]
          k = func "k"
          i = func "i"

ppTabDef ft id = char 'f' 
    <>  int id 
    <+> int 0 
    <+> (int $ lowTabSize ft)
    <+> (int $ lowTabGen ft) 
    <+> (hsep $ map double $ lowTabArgs ft)

ppStrset str id = text "strset" <+> int id <> comma <+> (dquotes $ text str)

-- file

newline = line

       
ppCsdFile flags instr0 instrs scores strTable tabs = 
    tag "CsoundSynthesizer" [
        tag "CsOptions" [flags],
        tag "CsInstruments" [
            instr0, strTable, instrs],
        tag "CsScore" [
            tabs, scores]]    

tag :: String -> [Doc] -> Doc
tag name content = vcat $ punctuate newline [
    char '<' <> text name <> char '>', 
    vcat $ punctuate newline content, 
    text "</" <> text name <> char '>']  

-- instrument

ppInstr :: InstrId -> Doc -> Doc
ppInstr instrId body = vcat [
    text "instr" <+> ppInstrId instrId,
    body,
    text "endin"]

ppInstr0 = vcat

ppOrc :: [Doc] -> Doc
ppOrc = vcat . punctuate newline

ppInstrId :: InstrId -> Doc
ppInstrId (InstrId den nom) = int nom <> maybe empty ppAfterDot den 
    where ppAfterDot x = text $ ('.': ) $ reverse $ show x

-- score

ppSco = vcat

ppScore = vcat

ppNote instrId time dur args = char 'i' <> ppInstrId instrId <+> double time <+> double dur <+> hsep args

ppMasterNote :: InstrId -> CsdEvent [Prim] -> Doc
ppMasterNote instrId evt = ppNote instrId (eventStart evt) (eventDur evt) (fmap ppPrim $ eventContent evt) <+> int 0

ppEvent :: InstrId -> CsdEvent [Prim] -> Var -> Doc
ppEvent instrId evt var = pre <> comma <+> ppVar var
    where pre = ppProc "event_i" $ dquotes (char 'i') : ppInstrId instrId 
                : (double $ eventStart evt) : (double $ eventDur evt) : (fmap ppPrim $ eventContent evt)

ppTotalDur d = text "f0" <+> double d

ppAlwayson :: InstrId -> Doc
ppAlwayson instrId = char 'i' <> ppInstrId instrId <+> int 0  <+> int (-1)

-- expressions

ppInline :: (a -> [Doc] -> Doc) -> Inline a Doc -> Doc
ppInline ppNode a = ppExp $ inlineExp a    
    where ppExp x = case x of
              InlinePrim n        -> inlineEnv a IM.! n
              InlineExp op args   -> ppNode op $ fmap ppExp args  

-- booleans

ppCondOp :: CondOp -> [Doc] -> Doc  
ppCondOp op = case op of
    TrueOp            -> const $ text "(1 == 1)"                
    FalseOp           -> const $ text "(0 == 1)"
    Not               -> uno "~" 
    And               -> bi "&&"
    Or                -> bi "||"
    Equals            -> bi "=="
    NotEquals         -> bi "!="
    Less              -> bi "<"
    Greater           -> bi ">"
    LessEquals        -> bi "<="    
    GreaterEquals     -> bi ">="                         
    where bi  = binaries 
          uno = unaries
          
-- numeric

ppNumOp :: NumOp -> [Doc] -> Doc
ppNumOp op = case  op of
    Add -> bi "+"
    Sub -> bi "-"
    Mul -> bi "*"
    Div -> bi "/"
    Neg -> uno "-"    
    Pow -> bi "^"    
    Mod -> bi "%"
    
    ExpOp -> fun "exp"
    IntOp -> fun "int" 
    
    x -> fun (firstLetterToLower $ show x)        
    where bi  = binaries
          uno = unaries
          fun = funcs
          firstLetterToLower (x:xs) = toLower x : xs


ppStmt :: [RatedVar] -> Exp RatedVar -> Doc
ppStmt outs exp = ppExp (ppOuts outs) exp

ppExp :: Doc -> Exp RatedVar -> Doc
ppExp res exp = case fmap ppPrimOrVar exp of
    ExpPrim (PString n) -> ppStrget res n
    ExpPrim p -> res $= ppPrim p
    Tfm info [a, b] | isInfix  info -> res $= binary (infoName info) a b
    Tfm info xs -> ppOpc res (infoName info) xs
    ConvertRate to from x -> ppConvertRate res to from x
    If info t e -> res $= ppIf (ppInline ppCondOp info) t e
    ExpNum (PreInline op as) -> res $= ppNumOp op as
    WriteVar v a -> ppVar v $= a
    ReadVar v -> res $= ppVar v
    x -> error $ "unknown expression: " ++ show x

          
