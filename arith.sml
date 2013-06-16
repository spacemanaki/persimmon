(* grammar:
exprs  -> expr exprs'
exprs' -> expr exprs'
exprs' ->
expr   -> term expr'
expr   -> if expr then expr else expr
expr   -> fn id => expr
expr   -> let id = expr in expr
expr'  -> + term expr'
expr'  ->
term   -> factor term'
term'  -> * factor term'
term'  ->
factor -> ( expr )
factor -> id
factor -> num
factor -> bool
*)

structure Lexer =
struct

datatype t = Num of int
           | Id of string
           | Bool of bool
           | LParen
           | RParen
           | Add
           | Mul
           | Div
           | Sub
           | If
           | Else
           | Then
           | Fn
           | Arrow
           | Let
           | Eq
           | In

fun show (Num n) = "Num " ^ Int.toString n
  | show (Bool b) = "Bool " ^ Bool.toString b
  | show (Id s) = "Id " ^ s
  | show LParen = "LParen"
  | show RParen = "RParen"
  | show Add = "Add"
  | show Mul = "Mul"
  | show Div = "Div"
  | show Sub = "Sub"
  | show If = "If"
  | show Else = "Else"
  | show Then = "Then"
  | show Fn = "Fn"
  | show Arrow = "Arrow"
  | show Let = "Let"
  | show Eq = "Eq"
  | show In = "In"

local

fun takeWhile p xs =
    let
       fun takeWhile' acc [] = (rev acc, [])
         | takeWhile' acc (all as x::xs) =
           if p x
              then takeWhile' (x::acc) xs
           else (rev acc, all)
    in
       takeWhile' [] xs
    end

fun getDigit chars =
    let
       val (numStr, rest) = takeWhile Char.isDigit chars
    in
       (Int.fromString (String.implode numStr), rest)
    end

fun getWord chars =
    let
       fun notDelim #"+" = false
         | notDelim #"-" = false
         | notDelim #"*" = false
         | notDelim #"/" = false
         | notDelim #"=" = false
         | notDelim #"(" = false
         | notDelim #")" = false
         | notDelim ch = not (Char.isSpace ch)
       val (word, rest) = takeWhile notDelim chars
    in
       (String.implode word, rest)
    end

exception LexicalError of string

in

fun lex (s : string) : t list =
    let
       fun lex' acc (#"(" :: rest) = lex' (LParen :: acc) rest
         | lex' acc (#")" :: rest) = lex' (RParen :: acc) rest
         | lex' acc (#"+" :: rest) = lex' (Add :: acc) rest
         | lex' acc (#"-" :: rest) = lex' (Sub :: acc) rest
         | lex' acc (#"*" :: rest) = lex' (Mul :: acc) rest
         | lex' acc (#"/" :: rest) = lex' (Div :: acc) rest
         | lex' acc (#"=" :: #">" :: rest) = lex' (Arrow :: acc) rest
         | lex' acc (#"=" :: rest) = lex' (Eq :: acc) rest
         | lex' acc (all as c :: cs) =
           if Char.isDigit c
              then case getDigit all of
                       (SOME n, rest) => lex' ((Num n) :: acc) rest
                     | (NONE, _) =>
                       raise LexicalError ("error lexing num: " ^ String.implode all)
           else if Char.isSpace c
                   then lex' acc cs
                else (case getWord all of
                         ("if", rest) => lex' (If :: acc) rest
                       | ("then", rest) => lex' (Then :: acc) rest
                       | ("else", rest) => lex' (Else :: acc) rest
                       | ("true", rest) => lex' (Bool true :: acc) rest
                       | ("false", rest) => lex' (Bool false :: acc) rest
                       | ("fn", rest) => lex' (Fn :: acc) rest
                       | ("let", rest) => lex' (Let :: acc) rest
                       | ("in", rest) => lex' (In :: acc) rest
                       | ("", _) =>
                         raise LexicalError ("error lexing: " ^ String.implode all)
                       | (id, rest) => lex' ((Id id) :: acc) rest)
         | lex' acc [] = rev acc
    in
       lex' [] (String.explode s)
    end
end
end

structure Parser =
struct

structure L = Lexer

datatype ast = Num of int
             | Bool of bool
             | Id of string
             | Add of ast * ast
             | Mul of ast * ast
             | Div of ast * ast
             | Sub of ast * ast
             | App of ast * ast
             | If of ast * ast * ast
             | Fn of string * ast
             | Let of string * ast * ast

fun show (Num n) = "Num " ^ Int.toString n
  | show (Bool b) = "Bool " ^ Bool.toString b
  | show (Id s) = "Id " ^ s
  | show (Add (lhs, rhs)) = "Add (" ^ show lhs ^ "," ^ show rhs ^ ")"
  | show (Sub (lhs, rhs)) = "Sub (" ^ show lhs ^ "," ^ show rhs ^ ")"
  | show (Mul (lhs, rhs)) = "Mul (" ^ show lhs ^ "," ^ show rhs ^ ")"
  | show (Div (lhs, rhs)) = "Div (" ^ show lhs ^ "," ^ show rhs ^ ")"
  | show (App (e1, e2)) = "App (" ^ show e1 ^ "," ^ show e2 ^ ")"
  | show (If (e1, e2, e3)) = "If (" ^ show e1 ^ "," ^ show e2 ^ "," ^ show e3 ^ ")"
  | show (Fn (x, e)) = "Fn (" ^ x ^ "," ^ show e ^ ")"
  | show (Let (x, e1, e2)) = "Let (" ^ x ^ "," ^ show e1 ^ "," ^ show e2 ^ ")"

exception SyntaxError of string
fun parse toks =
    let
       val rest = ref toks
       fun has () = not (null (!rest))
       fun adv () = rest := tl (!rest)
       fun next () = hd (!rest) before adv ()
       fun getNext () = if has () then SOME (next ()) else NONE
       fun peek () = hd (!rest)
       fun match tok = has () andalso tok = peek ()
       fun err s = raise SyntaxError ("err " ^ s)
       fun expected s t = raise SyntaxError ("expected " ^ s ^ ", got " ^ L.show t)
       val debug = false
       fun log s =
           let val t = if has () then L.show (peek ()) else ".."
           in if debug
                 then print (s ^ "(" ^ t ^ ")\n")
              else ()
           end

       fun expr () : ast =
           (log "expr";
            case peek () of
                L.If =>
                (adv ()
                ; let val e1 = exprs ()
                  in case peek () of
                         L.Then => (adv ()
                                   ; let val e2 = exprs ()
                                     in case peek () of
                                            L.Else => (adv ()
                                                      ; If (e1, e2, exprs ()))
                                          | t => expected "else" t
                                     end)
                       | t => expected "then" t
                  end)
              | L.Fn =>
                (adv ()
                ; case peek () of
                      L.Id x => (adv ()
                                ; case peek () of
                                      L.Arrow => (adv (); Fn (x, exprs ()))
                                    | t => expected "=>" t)
                    | t => err ("expected formal arg in fn expr, got " ^ L.show t))
              | L.Let =>
                (adv ()
                ; case peek () of
                      L.Id x => (adv ()
                                ; case peek () of
                                      L.Eq => (adv ()
                                              ; let val bound = exprs ()
                                                in case peek () of
                                                       L.In => (adv (); Let (x, bound, exprs ()))
                                                     | t => expected "in" t
                                                end)
                                    | t => expected "=" t)
                    | t => err ("expected bound var in let expr, got " ^ L.show t))
              | _ => expr' (term ()))

       and term () : ast =
           (log "term";
            let
               val lhs = factor ()
            in
               term' lhs
            end)

       and expr' (lhs : ast) : ast =
           (log "expr'";
           if has ()
              then case peek () of
                       L.Add => (next (); expr' (Add (lhs, term ())))
                     | L.Sub => (next (); expr' (Sub (lhs, term ())))
                     | _ => lhs
           else lhs)

       and term' (lhs : ast) : ast =
           (log "term'";
           if has ()
              then case peek () of
                       L.Mul => (next (); term' (Mul (lhs, factor ())))
                     | L.Div => (next (); term' (Div (lhs, factor ())))
                     | _ => lhs
           else lhs)

       and factor () : ast =
           (log "factor";
            case getNext () of
                SOME L.LParen => let val ast = exprs ()
                                 in case getNext () of
                                        SOME L.RParen => ast
                                      | SOME t => expected ")" t
                                      | _ => err "unexpected end of input, expected )"
                                 end
              | SOME (L.Num n) => Num n
              | SOME (L.Bool b) => Bool b
              | SOME (L.Id s) => Id s
              | SOME t => expected "bool, num or id" t
              | _ => err "unexpected end of input, expected bool, num or id")

       and exprs () : ast =
           let
              (* check if token is in FIRST(expr) *)
              fun FIRSTexpr (L.Id _) = true
                | FIRSTexpr (L.Num _) = true
                | FIRSTexpr (L.Bool _) = true
                | FIRSTexpr L.If = true
                | FIRSTexpr L.Fn = true
                | FIRSTexpr L.Let = true
                | FIRSTexpr L.LParen = true
                | FIRSTexpr _ = false

              val ast1 = expr ()
           in
              if has () andalso FIRSTexpr (peek ())
                 then App (ast1, expr ())
              else ast1
           end
    in
       exprs ()
    end

end

structure Tests =
struct
structure P = Parser
structure L = Lexer
val p = P.parse o L.lex
val parser = Test.group ("parser",
                         Test.polyEq {show = P.show},
[
fn _ => {expected = (P.Num 0),                                  actual = p "0"}
,fn _ => {expected = (P.Id "foo"),                                  actual = p "foo"}
,fn _ => {expected = P.Add (P.Num 1, P.Num 2),                  actual = p "1 + 2"}
,fn _ => {expected = P.Add (P.Mul (P.Num 1, P.Num 2), P.Num 3), actual = p "1 * 2 + 3"}
,fn _ => {expected = P.Sub (P.Num 1, P.Div (P.Num 2, P.Num 3)), actual = p "1 - 2 / 3"}
,fn _ => {expected = P.Mul (P.Sub (P.Num 1, P.Num 2), P.Num 3), actual = p "(1 - 2) * 3"}
,fn _ => {expected = P.Mul (P.Sub (P.Num 1, P.Num 2), P.Num 3), actual = p "(1 - 2) * (3)"}
,fn _ => {expected = P.Div (P.Sub (P.Id "bar", P.Num 2), P.Id "foo"), actual = p "(bar - 2) / foo"}
,fn _ => {expected = P.Sub (P.Add (P.Sub (P.Num 1, P.Num 2), P.Num 3), P.Num 4),
          actual = p "1 - 2 + 3 - 4"}

,fn _ => {expected = P.Fn ("x", P.Id "x"), actual = p "fn x=>x"}
,fn _ => {expected = P.Fn ("x", P.Fn ("y", P.Id "y")), actual = p "fn x => fn y => y"}
,fn _ => {expected = P.Fn ("x", P.Add (P.Id "x", P.Id "x")), actual = p "fn x => x + x"}
,fn _ => {expected = P.Fn ("x", P.Add (P.Id "x", P.Id "x")), actual = p "fn x=>x+x"}

,fn _ => {expected = P.Num 1, actual = p "(1)"}
,fn _ => {expected = P.Id "x", actual = p "(x)"}
,fn _ => {expected = P.Bool true, actual = p "(true)"}
,fn _ => {expected = P.If (P.Bool true, P.Id "x", P.Id "y"), actual = p "if (true) then (x) else ((y))"}

,fn _ => {expected = P.App (P.Id "x", P.Id "y"), actual = p "x y"}
,fn _ => {expected = P.App (P.Id "x", P.Id "y"), actual = p "(x y)"}
,fn _ => {expected = P.App (P.Fn ("x", P.Id "x"), P.Num 1), actual = p "(fn x => x) 1"}
,fn _ => {expected = P.Fn ("f", P.App (P.Id "f", P.Num 1)), actual = p "(fn f => f 1)"}
,fn _ => {expected = P.If (P.App (P.Id "not", P.Bool true), P.Bool false, P.Bool true), actual = p "if not true then false else true"}
,fn _ => {expected = P.If (P.Bool true, P.App (P.Id "not", P.Bool false), P.Bool true), actual = p "if true then not false else true"}
,fn _ => {expected = P.If (P.Bool true, P.Bool false, P.App (P.Id "not", P.Bool true)), actual = p "if true then false else not true"}
,fn _ => {expected = P.Let ("f", P.Fn ("x", P.Id "x"), P.App (P.Id "f", P.Num 1)), actual = p "let f = fn x => x in f 1"}

])
val lexer = Test.group ("lexer",
                        Test.polyEq {show = Show.list L.show},
[
fn _ => {expected = [L.Num 0],                                  actual = L.lex "0"}
,fn _ => {expected = [L.Fn, L.Id "x", L.Arrow, L.Id "x"],        actual = L.lex "fn x=>x"}
,fn _ => {expected = [L.Fn, L.Id "x", L.Arrow, L.Id "x"],        actual = L.lex "fn x => x"}
,fn _ => {expected = [L.If, L.Num 1, L.Then, L.Num 2, L.Else, L.Num 3], actual = L.lex "if 1 then 2 else 3"}
,fn _ => {expected = [L.If, L.Id "foo", L.Then, L.Id "bar", L.Else, L.Id "baz"], actual = L.lex "if foo then bar else baz"}
,fn _ => {expected = [L.Let, L.Id "x", L.Eq, L.Num 0, L.In, L.Id "x", L.Add, L.Id "x"], actual = L.lex "let x = 0 in x + x"}
,fn _ => {expected = [L.Let, L.Id "x", L.Eq, L.Num 0, L.In, L.Id "x", L.Add, L.Id "x"], actual = L.lex "let x=0 in x + x"}
])
fun main _ = (Test.runTestSuite (true, Test.concat [lexer, parser]);
              OS.Process.success)

end
