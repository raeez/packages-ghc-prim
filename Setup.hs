
-- We need to do some ugly hacks here because of GHC magic

module Main (main) where

import Control.Monad
import Data.List
import Distribution.PackageDescription
import Distribution.Simple
import Distribution.Simple.LocalBuildInfo
import Distribution.Simple.Utils
import System.Cmd
import System.FilePath
import System.Exit
import System.Directory
import Control.Exception (try)

main :: IO ()
main = do let hooks = defaultUserHooks {
                  regHook = addPrimModule
                          $ regHook defaultUserHooks,
                  buildHook = build_primitive_sources
                            $ buildHook defaultUserHooks,
                  makefileHook = build_primitive_sources
                               $ makefileHook defaultUserHooks,
                  haddockHook = build_primitive_sources
                               $ haddockHook defaultUserHooks }
          defaultMainWithHooks hooks

type Hook a = PackageDescription -> LocalBuildInfo -> UserHooks -> a -> IO ()

addPrimModule :: Hook a -> Hook a
addPrimModule f pd lbi uhs x =
    do let -- I'm not sure which one of these we actually need to change.
           -- It seems bad that there are two.
           pd' = addPrimModuleToPD pd
           lpd = addPrimModuleToPD (localPkgDescr lbi)
           lbi' = lbi { localPkgDescr = lpd }
       f pd' lbi' uhs x

addPrimModuleToPD :: PackageDescription -> PackageDescription
addPrimModuleToPD pd =
    case library pd of
    Just lib ->
        let ems = "GHC.Prim" : exposedModules lib
            lib' = lib { exposedModules = ems }
        in pd { library = Just lib' }
    Nothing ->
        error "Expected a library, but none found"

build_primitive_sources :: Hook a -> Hook a
build_primitive_sources f pd lbi uhs x
 = do when (compilerFlavor (compiler lbi) == GHC) $ do
          let genprimopcode = joinPath ["..", "..", "utils",
                                        "genprimopcode", "genprimopcode"]
              primops = joinPath ["..", "..", "compiler", "prelude",
                                  "primops.txt"]
              primhs = joinPath ["GHC", "Prim.hs"]
              primopwrappers = joinPath ["GHC", "PrimopWrappers.hs"]
              primhs_tmp = addExtension primhs "tmp"
              primopwrappers_tmp = addExtension primopwrappers "tmp"
          maybeExit $ system (genprimopcode ++ " --make-haskell-source < "
                           ++ primops ++ " > " ++ primhs_tmp)
          maybeUpdateFile primhs_tmp primhs
          maybeExit $ system (genprimopcode ++ " --make-haskell-wrappers < "
                           ++ primops ++ " > " ++ primopwrappers_tmp)
          maybeUpdateFile primopwrappers_tmp primopwrappers
      f pd lbi uhs x

-- Replace a file only if the new version is different from the old.
-- This prevents make from doing unnecessary work after we run 'setup makefile'
maybeUpdateFile :: FilePath -> FilePath -> IO ()
maybeUpdateFile source target = do
  r <- rawSystem "cmp" ["-s" {-quiet-}, source, target]
  case r of
    ExitSuccess   -> removeFile source
    ExitFailure _ -> do try (removeFile target); renameFile source target
