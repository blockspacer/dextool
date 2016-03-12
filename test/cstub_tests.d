// Written in the D programming language.
/**
Copyright: Copyright (c) 2015-2016, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
 */
module cstub_tests;

import scriptlike;
import utils;
import std.typecons : Flag, Yes, No;

import unit_threaded : Name, shouldEqual, ShouldFail;

enum globalTestdir = "c_tests";

struct TestParams {
    Flag!"skipCompare" skipCompare;
    Flag!"skipCompile" skipCompile;

    Path root;
    Path input_ext;
    Path out_hdr;
    Path out_impl;
    Path out_global;
    Path out_gmock;

    // dextool parameters;
    string[] dexParams;
    string[] dexFlags;

    // Compiler flags
    string[] compileFlags;
    string[] compileIncls;

    Path mainf;
}

TestParams genTestParams(string f, const ref TestEnv testEnv) {
    TestParams p;

    p.root = Path("testdata/cstub").absolutePath;
    p.input_ext = p.root ~ Path(f);

    p.out_hdr = testEnv.outdir ~ "test_double.hpp";
    p.out_impl = testEnv.outdir ~ "test_double.cpp";
    p.out_global = testEnv.outdir ~ "test_double_global.cpp";
    p.out_gmock = testEnv.outdir ~ "test_double_gmock.hpp";

    p.dexParams = ["--DRT-gcopt=profile:1", "ctestdouble", "--debug"];
    p.dexFlags = [];

    p.compileFlags = compilerFlags();
    p.compileIncls = ["-I" ~ p.input_ext.dirName.toString];

    p.mainf = p.root ~ Path("main1.cpp");

    return p;
}

void runTestFile(const ref TestParams p, ref TestEnv testEnv) {
    dextoolYap("Input:%s", p.input_ext.toRawString);
    runDextool(p.input_ext, testEnv, p.dexParams, p.dexFlags);

    if (!p.skipCompare) {
        dextoolYap("Comparing");
        auto input = p.input_ext.stripExtension;
        // dfmt off
        compareResult(
                      GR(input ~ Ext(".hpp.ref"), p.out_hdr),
                      GR(input ~ Ext(".cpp.ref"), p.out_impl),
                      GR(Path(input.toString ~ "_global.cpp.ref"), p.out_global),
                      GR(Path(input.toString ~ "_gmock.hpp.ref"), p.out_gmock));
        // dfmt on
    }

    if (!p.skipCompile) {
        dextoolYap("Compiling");
        compileResult(p.out_impl, p.mainf, testEnv, p.compileFlags, p.compileIncls);
    }
}

@Name("Should be correct declarations of arrays")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_1/arrays.h", testEnv);
    p.compileFlags ~= ["-DTEST_ARRAY", "-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@Name("Should ignore C++ code")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_1/class_func.hpp", testEnv);
    p.dexFlags = ["-xc++", "-DAND_A_DEFINE"];
    p.compileFlags ~= "-DTEST_INCLUDE";
    runTestFile(p, testEnv);
}

@Name("Should be global constants with defines to allow initialization")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_1/const.h", testEnv);
    p.compileFlags ~= ["-DTEST_CONST", "-DTEST_INCLUDE"];
    runTestFile(p, testEnv);
}

@Name("Should be plain function pointers or implementations")
unittest {
    //TODO split the test in two, "global func pointers"/"use typedef func prototype for declaration"
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_1/function_pointers.h", testEnv);
    p.compileFlags ~= "-DTEST_FUNC_PTR";
    runTestFile(p, testEnv);
}

@Name("Should be implementations of C functions")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_1/functions.h", testEnv);
    p.compileFlags ~= "-DTEST_INCLUDE";
    runTestFile(p, testEnv);
}

@Name(
        "Should be a google mock of the interface used as callback from the C function implementations")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_1/param_gmock.h", testEnv);
    p.dexParams ~= "--gmock";
    p.dexFlags ~= "-nostdinc";
    p.compileFlags ~= ["-DTEST_INCLUDE", "-DTEST_FUNC_PTR"];
    runTestFile(p, testEnv);
}

@Name("Interface and adapter should be affected by parameter --main=X")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_1/param_main.h", testEnv);
    p.dexParams ~= ["--main=Stub", "--main-fname=stub"];
    p.out_hdr = p.out_hdr.up ~ "stub.hpp";
    p.out_impl = p.out_impl.up ~ "stub.cpp";
    p.compileFlags = [];
    runTestFile(p, testEnv);
}

@Name("Should ignore the structs")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_1/structs.h", testEnv);
    p.compileFlags ~= "-DTEST_INCLUDE";
    runTestFile(p, testEnv);
}

@Name("Should use the internal headers in the binary even if -nostdinc is one of the compile flags")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_1/test_include_stdlibs.h", testEnv);
    // skip compiling, stdarg.h etc do not exist on all platforms
    p.skipCompile = Yes.skipCompile;
    runTestFile(p, testEnv);
}

@Name("Should ignore union declarations")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_1/unions.h", testEnv);
    p.compileFlags ~= "-DTEST_INCLUDE";
    runTestFile(p, testEnv);
}

@Name("Should be definitions of global variables for those that are extern")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_1/variables.h", testEnv);
    runTestFile(p, testEnv);
}

@Name("Should be an array using a macro for size")
unittest {
    //TODO Should use the original define (macro), not what it is replaced with
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_1/defines.h", testEnv);
    p.compileFlags ~= "-DTEST_INCLUDE";
    runTestFile(p, testEnv);
}

@Name("Should not overwrite an existing X_pre_includes or X_post_includes.hpp")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_2/no_overwrite.h", testEnv);
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;
    p.dexParams ~= ["--gen-pre-incl", "--gen-post-incl"];
    p.dexFlags ~= "-DPRE_INCLUDES";
    p.compileFlags ~= "-DPRE_INCLUDES";

    copy(p.root ~ "stage_2/no_overwrite_pre_includes.hpp",
            testEnv.outdir ~ "test_double_pre_includes.hpp");
    copy(p.root ~ "stage_2/no_overwrite_post_includes.hpp",
            testEnv.outdir ~ "test_double_post_includes.hpp");

    runTestFile(p, testEnv);
}

@Name("Should exclude many files from the generated test double")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_exclude_many_files.h", testEnv);
    p.dexParams ~= ["--file-exclude=.*/" ~ p.input_ext.baseName.toString,
        `--file-exclude='.*/include/b\.[h,c]'`];
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}

@Name("Should exclude both main input file and all symbols from b*")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_exclude_match_all.h", testEnv);
    p.dexParams ~= ["--file-exclude=.*/param_exclude_match_all.*",
        `--file-exclude='.*/include/b\.c'`];
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}

@Name("Should exclude this file from generation.")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_exclude_one_file.h", testEnv);
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;
    p.dexParams ~= "--file-exclude=.*/" ~ p.input_ext.baseName.toString;

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}

@Name("Should generate pre and post includes")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_gen_pre_post_include.h", testEnv);
    p.dexParams ~= ["--gen-pre-incl", "--gen-post-incl"];
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;
    p.skipCompare = Yes.skipCompare;

    runTestFile(p, testEnv);

    // dfmt off
    dextoolYap("Comparing");
    auto input = p.input_ext.stripExtension;
    compareResult(GR(input ~ Ext(".hpp.ref"), p.out_hdr),
                  GR(input ~ Ext(".cpp.ref"), p.out_impl),
                  GR(input.up ~ "param_gen_pre_includes.hpp.ref", testEnv.outdir ~ "test_double_pre_includes.hpp"),
                  GR(input.up ~ "param_gen_post_includes.hpp.ref", testEnv.outdir ~ "test_double_post_includes.hpp"));
    // dfmt on
}

@Name("Should be all from this and b with the extra include stdio.h")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_include.h", testEnv);
    p.dexParams ~= ["--td-include=b.h", "--td-include=stdio.h"];
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}

@Name("Should only be signatures from this file and b.h in the generated stub")
unittest {
    mixin(EnvSetup(globalTestdir));
    auto p = genTestParams("stage_2/param_restrict.h", testEnv);
    p.dexParams ~= ["--file-restrict=.*/" ~ p.input_ext.baseName.toString,
        "--file-restrict=.*/include/b.h"];
    p.compileIncls ~= "-I" ~ (p.root ~ "stage_2/include").toString;

    p.dexFlags = p.compileIncls;

    runTestFile(p, testEnv);
}
