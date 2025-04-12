-- DSL для реляционной алгебры
import Lean
import ERModel.Tables

open Lean Syntax
open Lean.Name
open Lean Elab Meta Syntax
open Lean.Parser.Term
open Lean.Parser.Command

declare_syntax_cat binding
syntax "(" ident " => " term ")" : binding
declare_syntax_cat schrow
syntax "(" str " : " ident ")" : schrow
declare_syntax_cat schema
syntax ident schrow* : schema
declare_syntax_cat tblrow
syntax "{ " term " }" : tblrow
declare_syntax_cat table
syntax ident tblrow* : table
declare_syntax_cat schematables
syntax "Tables " schema table* : schematables

syntax "RAModel " ident "where"
  "DBTypes" binding*
  schematables*
  "endRAModel" : command

def mkDBTypes (is : Array (TSyntax `ident)) (ts : Array (TSyntax `term))
  : MacroM (TSyntax `command) := do
  let attrNam := .mkSimple "DBType"
  let attrId := mkIdent attrNam
  let attrbind := mkIdent $ .str attrNam "asType"
  `(inductive $attrId : Type where $[| $is:ident]*
    deriving BEq, Repr
    open $(← `(Lean.Parser.Command.openDecl| $attrId:ident))
    def $attrbind : $attrId → Type $[| .$is:ident => $ts:term]*)

def mkRecode : MacroM (TSyntax `command) := do
  let mkId (s : String) := mkIdent $ mkSimple s
  let mkId2 (s₁ : String) (s₂ : String) := mkIdent $ mkStr2 s₁ s₂
  let schId := mkId "Schema"
  let dbt := mkIdent $ mkStr1 "DBType"
  let ast := mkIdent $ mkStr1 "asType"
  `(abbrev $(mkId "Column") : Type := Tables.Column $dbt
    abbrev $(mkId "Schema") : Type := Tables.Schema $dbt
    abbrev $(mkId "Subschema") : $schId → $schId → Type := Tables.Subschema $dbt
    abbrev $(mkId "Row") : $schId → Type := Tables.Row $dbt $ast
    abbrev $(mkId "Table") : $schId → Type := Tables.Table $dbt $ast
    abbrev $(mkId "HasCol") : $schId → String → $dbt → Type := Tables.HasCol $dbt
    def $(mkId2 "Schema" "renameColumn") {n t} : (s : $schId) → $(mkId "HasCol") s n t → String → $schId :=
      Tables.Schema.renameColumn $dbt
  )

def mkTbl (sch : TSyntax `ident) (acc : TSyntax `command) (tb : TSyntax `table) : MacroM (TSyntax `command) := do
  match tb with
  | `(table| $nm:ident $[{$item:term}]*) =>
    let tblNam := Name.mkSimple "Table"
    let tblId := mkIdent tblNam
    let mktbl ← `(command| def $nm:ident : $tblId $sch:ident := [ $[$item],* ])
    `($acc:command
      $mktbl)
  | _ => Macro.throwUnsupported

def mkSchTbls (acc : TSyntax `command) (st : TSyntax `schematables)
  : MacroM (TSyntax `command) := do
  match st with
  | `(schematables| Tables $nm:ident $[($f:str : $ty:ident)]* $tb:table*) =>
    -- dbg_trace "F={f}\n>>TY={ty}"
    let schId := mkIdent $ mkSimple "Schema"
    let mksch ← `(command| abbrev $nm:ident : $schId:ident := ([ $[⟨$f, $ty⟩],* ] : $schId))
    let mktbls ← tb.foldlM (mkTbl nm) $ TSyntax.mk mkNullNode
    `($acc:command
      $mksch:command
      $mktbls:command)
  | _ => Macro.throwUnsupported

macro_rules
| `(RAModel $ns:ident where
      DBTypes $[($is => $ts)]*
      $st:schematables*
    endRAModel) => do
    -- dbg_trace "ST={st}"
    let types ← mkDBTypes is ts
    let recode ← mkRecode --dbt  `asType
    let tbls ← st.foldlM mkSchTbls $ TSyntax.mk mkNullNode
    `(namespace $ns:ident
      $types:command
      $recode
      $tbls:command
      end $ns:ident)
