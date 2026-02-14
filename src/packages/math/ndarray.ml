open Ast

let numeric = function
  | VInt n -> Some (float_of_int n)
  | VFloat f -> Some f
  | VNA _ -> None
  | _ -> None

let shape_product (shape : int array) =
  Array.fold_left
    (fun acc d ->
       if d <= 0 then
         invalid_arg "shape dimensions must be strictly positive"
       else
         let max_allowed = max_int / d in
         if acc > max_allowed then
           invalid_arg "shape product: integer overflow computing total size"
         else
           acc * d)
    1
    shape

let parse_shape = function
  | VList dims ->
      let rec loop acc = function
        | [] -> Some (Array.of_list (List.rev acc))
        | (_, VInt n) :: tl when n > 0 -> loop (n :: acc) tl
        | _ -> None
      in
      loop [] dims
  | _ -> None

let rec infer_shape_and_flatten (v : value) : (int list * float list, value) result =
  match v with
  | VNA _ -> Error (Error.type_error "NDArray cannot contain NA values. Handle missingness explicitly.")
  | _ ->
      match numeric v with
      | Some f -> Ok ([], [f])
      | None ->
          match v with
          | VList items ->
              let elems = List.map snd items in
              let rec gather shape_acc data_acc = function
                | [] -> Ok (List.rev shape_acc, List.rev data_acc)
                | hd :: tl ->
                    (match infer_shape_and_flatten hd with
                     | Error e -> Error e
                     | Ok (shape, data) ->
                         gather (shape :: shape_acc) (data :: data_acc) tl)
              in
              (match gather [] [] elems with
               | Error e -> Error e
               | Ok (shapes, data_chunks) ->
                   let same_shape =
                     match shapes with
                     | [] -> true
                     | s0 :: rest -> List.for_all ((=) s0) rest
                   in
                   if not same_shape then
                     Error (Error.make_error ValueError "Cannot create NDArray from ragged (non-rectangular) list.")
                   else
                     let child_shape = match shapes with [] -> [] | s :: _ -> s in
                     let flat = List.concat data_chunks in
                     Ok ((List.length elems) :: child_shape, flat))
          | _ -> Error (Error.type_error "NDArray elements must be numeric.")

let value_of_shape shape =
  VList (shape |> Array.to_list |> List.map (fun d -> (None, VInt d)))

let ndarray_create args =
  match args with
  | [data] ->
      (match infer_shape_and_flatten data with
       | Error e -> e
       | Ok (shape, flat) ->
           let shape_arr = Array.of_list shape in
           if Array.exists (fun d -> d <= 0) shape_arr then
             Error.make_error ValueError "NDArray shape dimensions must be strictly positive."
           else
             VNDArray { shape = shape_arr; data = Array.of_list flat })
  | [data; shape_v] ->
      (match parse_shape shape_v with
       | None -> Error.type_error "ndarray(shape=...) expects shape as a List of positive Ints."
       | Some shape ->
           (match infer_shape_and_flatten data with
            | Error e -> e
            | Ok (_, flat) ->
                (try
                   let expected = shape_product shape in
                   if expected <> List.length flat then
                     Error.make_error ValueError
                       (Printf.sprintf "Shape [%s] requires %d elements, got %d."
                          (shape |> Array.to_list |> List.map string_of_int |> String.concat ", ")
                          expected (List.length flat))
                   else VNDArray { shape; data = Array.of_list flat }
                 with Invalid_argument msg ->
                   Error.make_error ValueError msg)))
  | _ -> Error.make_error ArityError "Function `ndarray` takes 1 or 2 arguments."

let reshape args =
  match args with
  | [VNDArray arr; shape_v] ->
      (match parse_shape shape_v with
       | None -> Error.type_error "reshape expects shape as a List of positive Ints."
       | Some shape ->
           (try
              let expected = shape_product shape in
              if expected <> Array.length arr.data then
                Error.make_error ValueError "reshape target shape must preserve element count."
              else VNDArray { shape; data = Array.copy arr.data }
            with Invalid_argument msg ->
              Error.make_error ValueError msg))
  | _ -> Error.type_error "reshape expects (NDArray, shape)."

let matrix_multiply args =
  match args with
  | [VNDArray a; VNDArray b] ->
      if Array.length a.shape <> 2 || Array.length b.shape <> 2 then
        Error.make_error ValueError "matmul expects two 2D NDArrays."
      else
        let m = a.shape.(0) and k1 = a.shape.(1) in
        let k2 = b.shape.(0) and n = b.shape.(1) in
        if k1 <> k2 then
          Error.make_error ValueError "matmul inner dimensions must match."
        else
          let out = Array.make (m * n) 0.0 in
          for i = 0 to m - 1 do
            for j = 0 to n - 1 do
              let sum = ref 0.0 in
              for k = 0 to k1 - 1 do
                sum := !sum +. a.data.(i * k1 + k) *. b.data.(k * n + j)
              done;
              out.(i * n + j) <- !sum
            done
          done;
          VNDArray { shape = [|m; n|]; data = out }
  | _ -> Error.type_error "matmul expects two NDArrays."

let kron args =
  match args with
  | [VNDArray a; VNDArray b] ->
      if Array.length a.shape <> 2 || Array.length b.shape <> 2 then
        Error.make_error ValueError "kron expects two 2D NDArrays."
      else
        let ar = a.shape.(0) and ac = a.shape.(1) in
        let br = b.shape.(0) and bc = b.shape.(1) in
        let out_rows = ar * br and out_cols = ac * bc in
        let out = Array.make (out_rows * out_cols) 0.0 in
        for i = 0 to ar - 1 do
          for j = 0 to ac - 1 do
            let aij = a.data.(i * ac + j) in
            for p = 0 to br - 1 do
              for q = 0 to bc - 1 do
                let row = i * br + p in
                let col = j * bc + q in
                out.(row * out_cols + col) <- aij *. b.data.(p * bc + q)
              done
            done
          done
        done;
        VNDArray { shape = [|out_rows; out_cols|]; data = out }
  | _ -> Error.type_error "kron expects two NDArrays."

let shape_of args =
  match args with
  | [VNDArray arr] -> value_of_shape arr.shape
  | _ -> Error.type_error "shape expects an NDArray."

let data_of args =
  match args with
  | [VNDArray arr] ->
      VList (arr.data |> Array.to_list |> List.map (fun f -> (None, VFloat f)))
  | _ -> Error.type_error "ndarray_data expects an NDArray."

let register env =
  let env = Env.add "ndarray"
      (make_builtin ~variadic:true 1 (fun args _env -> ndarray_create args)) env in
  let env = Env.add "reshape"
      (make_builtin 2 (fun args _env -> reshape args)) env in
  let env = Env.add "shape"
      (make_builtin 1 (fun args _env -> shape_of args)) env in
  let env = Env.add "ndarray_data"
      (make_builtin 1 (fun args _env -> data_of args)) env in
  let env = Env.add "matmul"
      (make_builtin 2 (fun args _env -> matrix_multiply args)) env in
  let env = Env.add "kron"
      (make_builtin 2 (fun args _env -> kron args)) env in
  env
