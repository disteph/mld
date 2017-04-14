# mld
Ocamlbuild plugin: turns directory `foo.mld` into a module `Foo`.

The contents of module `Foo` are the modules that can be "found" in directory `foo.mld` and recursively in its subdirectories,
down to other directories of the form `bar.mld`:
`Bar` will be a submodule of `Foo`, and the recursive search for `Foo`'s modules stops there.
The contents of `bar.mld` will then be used to determine the submodules of `Foo.Bar`.
Hence, the following source tree

```
-src/
 |-foo.mld/
   |-a/
   | |-bar.mld/
   | | |-b.ml
   | |
   | |-c/
   |   |-d.ml
   |
   |-e.ml
```

will turn into the following module structure

```
-Foo
 |-Bar
 | |-B
 |
 |-D
 |-E
```

In the background:
an mlpack is automatically generated for each directory *.mld, and the `-for-pack` options are automatically generated.


### Directory visibility

All directories scanned for `Foo`'s contents (i.e. `src/foo.mld`, `src/foo.mld/a`, `src/foo.mld/a/c`) can see each other, as if they were flattened.
So `D` and `E` can refer to each other (in a non-circular way).
On the other hand they cannot see the contents of `bar.mld`: module `B` will be unknown to them, but they can instead refer to `Bar.B`.

In the other direction,
the default behaviour is that directory `bar.mld` inherits the visibility of the upper group,
so that `B` can see its uncles and aunts, i.e. refer to `D` and `E` (if it refers to `Bar`, a circularity would be detected).
Likewise, all of the directories inherit the visibility of `src`,
so that all of the modules mentioned here can refer to the brothers of `Foo` available in directory `src`.

This default behaviour can be changed (e.g. if we had a file `d.ml` in directory `bar.mld`, which would create an ambiguity),
by the use of a new Ocamlbuild tag:
```
<target_dir.mld> : blind
```
in Ocamlbuild's `_tags` file would prevent the contents of `target_dir.mld` to inherit the visibility of the directory where `target_dir.mld` sits.
Here, `<src/foo.mld/a/bar.mld> : blind` in the `_tags` file would prevent `B` from referring to its uncles and aunts `D` and `E`.



### Other tagging possibilities added to ocamlbuild's

The plugin offers two new tags to be used in ocamlbuild:
`visible(directory_path)` and `invisible(directory_path)`.

For instance in ocamlbuild's `_tags` file one can write
```
<target_dir> : visible(directory_path)
```
whose effect is that `target_dir` can see the contents of `directory_path`,
i.e. any target in directory `target_dir` has the include flag `-I directory_path`.

Similarly,
```
<target_dir> : invisible(directory_path)
```
removes `directory_path` from the directories visible by `target_dir`.
(Note that these rules are applied before the 'visibility inheritance' mechanism for mld directories,
which could make `directory_path` visible again by `target_dir`).

Finally, the plugin introduces a phony target called 'silent':
writing
```
<silent> : tag1, tag2, tag3
```
in the `_tags` file
makes Ocamlbuild's unused tag detection mechanism for `tag1`, `tag2`, and `tag3`, finally shut up.
No more warnings of this kind when you know what you are doing.

### Installation

This is a standard oasis-managed library:
```
oasis setup
ocaml setup.ml -configure
ocaml setup.ml -build
ocaml setup.ml -install
```
will install the library with findlib

Hopefully soon, I will register the package with opam, so that one can directly type
```
opam install mld
```
to have the same effect as above.

### Usage

The dispatch function `Mld.dispatch` should be called by `myocamlbuild.ml` with a line like
```
let () = Ocamlbuild_plugin.dispatch Mld.dispatch
```
or if you already have another dispatch function (provided by e.g. oasis)
```
let () = Ocamlbuild_plugin.dispatch
             (MyOCamlbuildBase.dispatch_combine
                 [ other_dispatch ; Mld.dispatch ])
```

Then when calling ocamlbuild, you need to indicate that Findlib's package `mld` should be used, e.g.
```
ocamlbuild -use-ocamlfind -plugin-tags 'package(mld)' ...
```

With oasis, you need something like

```
BuildTools:  ocamlbuild
OCamlVersion:           >= 4.03
AlphaFeatures:          ocamlbuild_more_args
XOCamlbuildPluginTags:  package(mld)
```

### License

This package is distributed under the terms of the [CeCILL-C License](http://www.cecill.info/licences/Licence_CeCILL-C_V1-en.html).
