open Ocamlbuild_plugin

let print_info f =
  Format.fprintf Format.std_formatter
    "@[<hv 2>Tags for file %s:@ %a@]@." f
    Tags.print (tags_of_pathname f)

let concat a b = Pathname.normalize(Pathname.concat a b)
let parent_dir dir = concat dir (Pathname.parent "")

let scan4tag tag path =
  path |> tags_of_pathname |> (Tags.mem tag)
                                
let tag_regexp tag =
  Str.regexp (Printf.sprintf "%s\\((\\([^)]*\\))\\)?$" tag)

let rec scan4ptag ptag path =
  let aux tag sofar = 
    if not @@ Str.string_match (tag_regexp ptag) tag 0
    then sofar
    else
      try (Str.matched_group 2 tag)::sofar
      with Not_found ->
        Printf.sprintf
          "The %s tag requires an argument"
          ptag
        |> failwith
  in
  List.fold_right aux (path |> tags_of_pathname |> Tags.elements) []
                                       
let mk_visible dirlist dir =
  let dirlist = List.sort_uniq String.compare (dirlist@Pathname.include_dirs_of dir) in
  Pathname.define_context dir dirlist

let mk_all_visible inherited dirlist =
  List.iter (mk_visible (inherited@dirlist)) dirlist

let ml_rule env build =
  try
    let ml = env "%.mlpack" and mld = env "%.mld" in
    let main_dir   = parent_dir !Options.build_dir in
    let orig_mld   = concat main_dir mld in
    let here       = Pathname.dirname mld in
    let thismodule = module_name_of_pathname mld in

    if not(Pathname.exists orig_mld)
    then raise Ocamlbuild_pack.Rule.Failed;

    let dir,packs =
      if Pathname.is_directory orig_mld
      then mld, []
      else Pathname.remove_extension mld,
           string_list_of_file orig_mld
    in
    let packs = packs@(scan4ptag "for-pack" mld) in
    let packs = match packs with
      | [] -> [thismodule]
      | _  -> List.map
                (fun sofar -> sofar^"."^thismodule)
                packs
    in

    let rec treat_dir subdir (accu,deps,ctx) =
      let relpath  = concat here subdir in
      let fullpath = concat main_dir relpath in
      (* print_endline("Collecting modules from files in "^subdir); *)
      let ctx = relpath::ctx in
      let contents = Pathname.readdir fullpath in
      let treatfile x = treat_file (concat subdir x) in
      Array.fold_right treatfile contents (accu,deps,ctx)

    and treat_file file (accu,deps,ctx) =
      let relpath   = concat here file in
      let orig_path = concat main_dir relpath in
      (* print_endline("Treating file "^fullpath); *)
      let check = Pathname.check_extension file in
      if List.exists check ["ml";"mlpack";"mld";"mly";"mll"]
      then
        (let base = Pathname.remove_extension relpath in
         let cmx = Pathname.add_extension "cmx" base in
         let cmo = Pathname.add_extension "cmo" base in
         let src =
           if check "mld" then Pathname.add_extension "mlpack" base
           else relpath
         in
         let pack_aux pack sofar =
           tag_file relpath ["for-pack("^pack^")"];
           A"-for-pack"::A pack::sofar
         in
         let pack_command = S(List.fold_right pack_aux packs []) in
         flag ["ocaml"; "compile"; "file:"^cmx] & pack_command;
         flag ["ocaml"; "compile"; "file:"^cmo] & pack_command;
         flag ["ocaml"; "pack"; "file:"^cmx] & pack_command;
         flag ["ocaml"; "pack"; "file:"^cmo] & pack_command;
         let modle = module_name_of_pathname file in
         ((concat (Pathname.dirname file) modle)^"\n")::accu,
         [src]::deps,
         ctx)
      else if (Pathname.is_directory orig_path)
              && not(Pathname.exists (Pathname.add_extension "mld" orig_path))
      then treat_dir file (accu,deps,ctx)
      else accu,deps,ctx
    in
    
    let mlstring,deps,ctx  = treat_dir (Pathname.basename dir) ([],[],[]) in
    let inherited =
      if scan4tag "blind" mld
      then []
      else Pathname.include_dirs_of here
    in
    mk_all_visible inherited ctx;
    List.iter Outcome.ignore_good(build deps);

    Echo(mlstring,ml)
  with
    _ -> raise Ocamlbuild_pack.Rule.Failed


      
let visible_rule env build =
  let target = env "%" in
  let dir = Pathname.dirname target in
  (* print_info dir; *)
  (* print_endline("Target is: "^target); *)
  (* print_endline("Dir is: "^dir); *)
  let aux visible =
    let include_dirs = Pathname.include_dirs_of dir in
    if not(List.mem visible include_dirs)
    then Pathname.define_context dir (visible::include_dirs)
      (* print_endline("Making "^visible^" visible to "^dir); *)
  in
  List.iter aux (scan4ptag "visible" dir);
  let invisible = scan4ptag "invisible" dir in
  let aux path  = not(List.mem path invisible) in
  let include_dirs = List.filter aux (Pathname.include_dirs_of dir) in
  Pathname.define_context dir include_dirs;
  raise Ocamlbuild_pack.Rule.Failed
  

let dispatch = function
  | After_rules ->
     (* This is just to silence the warnings "Tag ... not used"
        declared as tags of "silent" *)
     List.iter mark_tag_used ("silent" |> tags_of_pathname |> Tags.elements);
     (* Never raise warning for tag "blind" *)
     mark_tag_used "blind";
     (* This is just to silence all warnings
        "Tag visible(...) not used" and "Tag invisible(...) not used" *)
     pflag [] "visible" (fun _ -> N);
     pflag [] "invisible" (fun _ -> N);
     rule "mld -> mlpack" ~prod:"%.mlpack" ml_rule;
     rule "compute local includes" ~prod:"%" ~insert:(`top) visible_rule
  | _ -> ()

