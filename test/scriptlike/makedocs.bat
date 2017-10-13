@echo off

echo Note, generating Scriptlike's docs requires that dub
echo ^<http://code.dlang.org/download^> be available on your PATH.
echo.
echo You must also have ddox and gen-package-version available through dub:
echo ^> dub fetch ddox --version=0.15.18
echo ^> dub fetch gen-package-version --version=1.0.5
echo or:
echo ^> dub add-local [path/to/ddox]
echo ^> dub add-local [path/to/gen-package-version]
echo.
echo You may need to remove any older versions installed
echo so they don't get run instead.
echo.
echo If you get errors, double-check you have dub, ddox and gen-package-version
echo all installed as described above.
echo.

dub run gen-package-version -- scriptlike --src=src --ddoc=ddoc
rdmd -Isrc -Iddoc --build-only --force -c -Dddocs_tmp -X -Xfdocs\docs.json -version=docs_scriptlike_d src\scriptlike\package.d
rmdir /S /Q docs_tmp > NUL 2> NUL
del src\scriptlike\package.obj
dub run ddox -- filter docs\docs.json --min-protection=Protected --ex=scriptlike.packageVersion
dub run ddox -- generate-html docs\docs.json docs\public --navigation-type=ModuleTree --override-macros=ddoc\macros.ddoc --override-macros=ddoc\packageVersion.ddoc
