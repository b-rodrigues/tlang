(* src/packages/stats/distributions.ml *)
open Ast

(* --- Math Primitives --- *)

(** Log-gamma via Lanczos approximation *)
let log_gamma v =
  let g = 7.0 in
  let coefs = [| 0.99999999999980993; 676.5203681218851; -1259.1392167224028;
                 771.32342877765313; -176.61502916214059; 12.507343278686905;
                 -0.13857109526572012; 9.9843695780195716e-6; 1.5056327351493116e-7 |] in
  if v < 0.5 then
    let pi = Float.pi in
    log pi -. log (Float.abs (sin (pi *. v))) -. (let lg v = 
      let vv = v -. 1.0 in
      let x = ref coefs.(0) in
      for i = 1 to 8 do
        x := !x +. coefs.(i) /. (vv +. float_of_int i)
      done;
      let t = vv +. g +. 0.5 in
      0.5 *. log (2.0 *. Float.pi) +. (vv +. 0.5) *. log t -. t +. log !x
    in lg (1.0 -. v))
  else begin
    let vv = v -. 1.0 in
    let x = ref coefs.(0) in
    for i = 1 to 8 do
      x := !x +. coefs.(i) /. (vv +. float_of_int i)
    done;
    let t = vv +. g +. 0.5 in
    0.5 *. log (2.0 *. Float.pi) +. (vv +. 0.5) *. log t -. t +. log !x
  end

(** Regularised incomplete gamma function P(a, x) = gamma(a, x) / Gamma(a) *)
let gammp a x =
  if x < 0.0 || a <= 0.0 then 0.0
  else if x < a +. 1.0 then begin
    (* Series representation *)
    let gln = log_gamma a in
    let rec loop n ap sum =
      let ap = ap +. 1.0 in
      let del = sum *. x /. ap in
      let sum = sum +. del in
      if Float.abs del < Float.abs sum *. 3.0e-12 || n > 100 then sum
      else loop (n + 1) ap sum
    in
    exp (a *. log x -. x -. gln) *. (loop 0 a (1.0 /. a))
  end else begin
    (* Continued fraction representation (Lentz's method) *)
    let gln = log_gamma a in
    let b = x +. 1.0 -. a in
    let fpmin = 1.0e-30 in
    let h = ref b in
    if Float.abs !h < fpmin then h := fpmin;
    let c = ref !h in
    let d = ref 0.0 in
    let i = ref 1 in
    let converged = ref false in
    while !i <= 100 && not !converged do
      let an = -. float_of_int !i *. (float_of_int !i -. a) in
      let b_i = x +. float_of_int (2 * !i + 1) -. a in
      d := b_i +. an *. !d;
      if Float.abs !d < fpmin then d := fpmin;
      c := b_i +. an /. !c;
      if Float.abs !c < fpmin then c := fpmin;
      d := 1.0 /. !d;
      let del = !d *. !c in
      h := !h *. del;
      if Float.abs (del -. 1.0) < 3.0e-12 then converged := true;
      incr i
    done;
    1.0 -. exp (a *. log x -. x -. gln) *. (1.0 /. !h)
  end

(** Regularised incomplete beta function I_x(a, b) *)
let betai x a b =
  if x <= 0.0 then 0.0
  else if x >= 1.0 then 1.0
  else begin
    let gln = log_gamma (a +. b) -. log_gamma a -. log_gamma b in
    let continued_fraction a b x =
      let qab = a +. b in
      let qap = a +. 1.0 in
      let qam = a -. 1.0 in
      let c = 1.0 in
      let d = 1.0 -. qab *. x /. qap in
      let d = if Float.abs d < 1.0e-30 then 1.0e-30 else d in
      let d = 1.0 /. d in
      let h = d in
      let rec loop m d h c =
        let m_f = float_of_int m in
        let m2 = 2.0 *. m_f in
        let aa = m_f *. (b -. m_f) *. x /. ((qam +. m2) *. (a +. m2)) in
        let d = 1.0 +. aa *. d in
        let d = if Float.abs d < 1.0e-30 then 1.0e-30 else d in
        let c = 1.0 +. aa /. c in
        let c = if Float.abs c < 1.0e-30 then 1.0e-30 else c in
        let d = 1.0 /. d in
        let h = h *. d *. c in
        let aa = -. (a +. m_f) *. (qab +. m_f) *. x /. ((a +. m2) *. (qap +. m2)) in
        let d = 1.0 +. aa *. d in
        let d = if Float.abs d < 1.0e-30 then 1.0e-30 else d in
        let c = 1.0 +. aa /. c in
        let c = if Float.abs c < 1.0e-30 then 1.0e-30 else c in
        let d = 1.0 /. d in
        let del = d *. c in
        let h = h *. del in
        if Float.abs (del -. 1.0) < 3.0e-12 then h
        else if m > 100 then h
        else loop (m + 1) d h c
      in
      loop 1 d h c
    in
    if x < (a +. 1.0) /. (a +. b +. 2.0) then
      exp (gln +. a *. log x +. b *. log (1.0 -. x)) /. a *. (continued_fraction a b x)
    else
      1.0 -. exp (gln +. b *. log (1.0 -. x) +. a *. log x) /. b *. (continued_fraction b a (1.0 -. x))
  end

(* --- Statistical Distributions (CDFs) --- *)

let pnorm x =
  (* Approximation for Normal CDF *)
  let t = 1.0 /. (1.0 +. 0.2316419 *. (Float.abs x)) in
  let d = 0.3989423 *. exp (-. x *. x /. 2.0) in
  let prob = d *. t *. (0.3193815 +. t *. (-0.3565638 +. t *. (1.781478 +. t *. (-1.821256 +. t *. 1.330274)))) in
  if x > 0.0 then 1.0 -. prob else prob

let pt x df =
  let x2 = x *. x in
  let df_f = float_of_int df in
  let beta_x = df_f /. (df_f +. x2) in
  let p = 0.5 *. betai beta_x (0.5 *. df_f) 0.5 in
  if x > 0.0 then 1.0 -. p else p

let pf q df1 df2 =
  let df1_f = float_of_int df1 in
  let df2_f = float_of_int df2 in
  let x = df2_f /. (df2_f +. df1_f *. q) in
  1.0 -. betai x (0.5 *. df2_f) (0.5 *. df1_f)

let pchisq q df =
  gammp (0.5 *. float_of_int df) (0.5 *. q)

(* --- Registration --- *)

(*
--# Normal distribution CDF
--#
--# Returns cumulative probabilities from the standard normal distribution.
--#
--# @name pnorm
--# @param x :: Float The value at which to evaluate the CDF.
--# @return :: Float The cumulative probability.
--# @family stats
--# @export
*)
(*
--# Student t distribution CDF
--#
--# Returns cumulative probabilities from the Student t distribution.
--#
--# @name pt
--# @param x :: Float The value at which to evaluate the CDF.
--# @param df :: Int Degrees of freedom.
--# @return :: Float The cumulative probability.
--# @family stats
--# @export
*)
(*
--# F distribution CDF
--#
--# Returns cumulative probabilities from the F distribution.
--#
--# @name pf
--# @param q :: Float The value at which to evaluate the CDF.
--# @param df1 :: Int Degrees of freedom 1.
--# @param df2 :: Int Degrees of freedom 2.
--# @return :: Float The cumulative probability.
--# @family stats
--# @export
*)
(*
--# Chi-squared distribution CDF
--#
--# Returns cumulative probabilities from the chi-squared distribution.
--#
--# @name pchisq
--# @param q :: Float The value at which to evaluate the CDF.
--# @param df :: Int Degrees of freedom.
--# @return :: Float The cumulative probability.
--# @family stats
--# @export
*)
let register env =
  let env = Env.add "pnorm" (make_builtin ~name:"pnorm" 1 (fun args _env ->
    match args with
    | [VFloat x] -> VFloat (pnorm x)
    | [VInt x] -> VFloat (pnorm (float_of_int x))
    | _ -> Error.type_error "pnorm expects a numeric argument."
  )) env in
  let env = Env.add "pt" (make_builtin ~name:"pt" 2 (fun args _env ->
    match args with
    | [VFloat x; VInt df] -> VFloat (pt x df)
    | [VInt x; VInt df] -> VFloat (pt (float_of_int x) df)
    | _ -> Error.type_error "pt expects (numeric, Int)."
  )) env in
  let env = Env.add "pf" (make_builtin ~name:"pf" 3 (fun args _env ->
    match args with
    | [VFloat q; VInt df1; VInt df2] -> VFloat (pf q df1 df2)
    | [VInt q; VInt df1; VInt df2] -> VFloat (pf (float_of_int q) df1 df2)
    | _ -> Error.type_error "pf expects (numeric, Int, Int)."
  )) env in
  let env = Env.add "pchisq" (make_builtin ~name:"pchisq" 2 (fun args _env ->
    match args with
    | [VFloat q; VInt df] -> VFloat (pchisq q df)
    | [VInt q; VInt df] -> VFloat (pchisq (float_of_int q) df)
    | _ -> Error.type_error "pchisq expects (numeric, Int)."
  )) env in
  env
