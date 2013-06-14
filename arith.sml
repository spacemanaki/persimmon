(* grammar:
expr   -> term expr'
expr'  -> + term expr'
expr'  ->
term   -> factor term'
term'  -> * factor term'
term'  ->
factor -> ( expr )
factor -> id
*)

structure Lexer =
struct

datatype t = Num of int
           | LParen
           | RParen
           | Add
           | Mul
           | Div
           | Sub

fun show (Num n) = "Num " ^ Int.toString n
  | show LParen = "LParen"
  | show RParen = "RParen"
  | show Add = "Add"
  | show Mul = "Mul"
  | show Div = "Div"
  | show Sub = "Sub"

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
         | lex' acc (all as c :: cs) =
           if Char.isDigit c
              then case getDigit all of
                       (SOME n, rest) => lex' ((Num n) :: acc) rest
                     | (NONE, _) =>
                       raise LexicalError ("error lexing num: " ^ String.implode all)
           else if Char.isSpace c
                   then lex' acc cs
                else raise LexicalError ("unknown char: " ^ Char.toString c)
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
             | Add of ast * ast
             | Mul of ast * ast
             | Div of ast * ast
             | Sub of ast * ast

fun show (Num n) = "Num " ^ Int.toString n
  | show (Add (lhs, rhs)) = "Add (" ^ show lhs ^ "," ^ show rhs ^ ")"
  | show (Sub (lhs, rhs)) = "Sub (" ^ show lhs ^ "," ^ show rhs ^ ")"
  | show (Mul (lhs, rhs)) = "Mul (" ^ show lhs ^ "," ^ show rhs ^ ")"
  | show (Div (lhs, rhs)) = "Div (" ^ show lhs ^ "," ^ show rhs ^ ")"

fun isNum (L.Num _) = true
  | isNum _ = false

exception SyntaxError of string
fun parse toks =
    let
       val idx = ref 0
       val arr = Array.fromList toks
       fun has () = !idx < Array.length arr
       fun adv () = idx := !idx + 1
       fun next () = Array.sub (arr, !idx) before adv ()
       fun getNext () = if has () then SOME (next ()) else NONE
       fun peek () = Array.sub (arr, !idx)
       fun match tok = has () andalso tok = peek ()
       fun err s = raise SyntaxError ("err " ^ s)
       val debug = true
       fun log s =
           let val t = if has () then L.show (peek ()) else ".."
           in if debug
                 then print (s ^ "(" ^ t ^ ")\n")
              else ()
           end

       fun expr () : ast =
           (log "expr";
            let
               val lhs = term ()
            in
               expr' lhs
            end)

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
           if match L.LParen
              then (next ()
                   ; let val ast = expr ()
                     in if match L.RParen
                           then (adv (); ast)
                        else err ")"
                     end)
           else if has ()
                then case next () of
                         L.Num n => Num n
                       | _ => err "digit"
                else err "digit")
    in
       expr ()
    end

end
