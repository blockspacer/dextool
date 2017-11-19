/**
Copyright: Copyright (c) 2017, Joakim Brännström. All rights reserved.
License: MPL-2
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

This Source Code Form is subject to the terms of the Mozilla Public License,
v.2.0. If a copy of the MPL was not distributed with this file, You can obtain
one at http://mozilla.org/MPL/2.0/.
*/
module dextool.plugin.mutate.backend.mutate_uoi;

import logger = std.experimental.logger;
import std.typecons : Nullable;

import dextool.type : AbsolutePath, FileName, Exists;

import dextool.clang_extensions;

import dextool.plugin.mutate.backend.visitor : MutationPoint;

@safe:

void uoiMutate(const Exists!AbsolutePath input_file, const AbsolutePath output_dir,
        const string[] cflags, const Nullable!size_t in_mutation_point) {
    import std.typecons : Yes;
    import cpptooling.analyzer.clang.context : ClangContext;
    import dextool.type : ExitStatusType;
    import dextool.utility : analyzeFile;
    import dextool.plugin.mutate.backend.visitor : ExpressionVisitor;

    auto ctx = ClangContext(Yes.useInternalHeaders, Yes.prependParamSyntaxOnly);
    auto visitor = new ExpressionVisitor;
    auto exit_status = analyzeFile(input_file, cflags, visitor, ctx);

    if (exit_status != ExitStatusType.Ok) {
        logger.error("Unable to mutate: ", cast(string) input_file);
        return;
    } else if (visitor.mutationPoints.length == 0) {
        logger.error("No mutation points in: ", cast(string) input_file);
        return;
    }

    logger.info("Total number of mutation points: ", visitor.mutationPoints.length);

    const size_t mut_point = randomMutationPoint(in_mutation_point, visitor.mutationPoints.length);

    logger.info("Mutation point ", mut_point);

    const auto mp = visitor.mutationPoints()[mut_point];

    import std.conv : to;
    import std.stdio : File;
    import std.path : buildPath, baseName;
    import dextool.plugin.mutate.backend.vfs;

    foreach (idx, kind; mutations(mp)) {
        const output_file = buildPath(output_dir, idx.to!string ~ input_file.baseName);
        auto s = ctx.virtualFileSystem.drop!(void[])(input_file, mp.offset);

        auto fout = File(output_file, "w");

        // trusted: is safe in dmd-2.077.0. Remove trusted in the future
        () @trusted{ fout.rawWrite(s.front); }();
        s.popFront;

        const mut_to = mutate(mp.spelling, kind);

        // trusted: is safe in dmd-2.077.0. Remove trusted in the future
        () @trusted{ fout.write(mut_to); fout.rawWrite(s.front); }();

        logger.infof("Mutated from '%s' to '%s' at %s", mp.spelling, mut_to, mp.location);
    }
}

private:

import std.format : format;

enum MutateKind {
    preInc,
    preDec,
    postInc,
    postDec,
    address,
    indirection,
    positive,
    negative,
    complement,
    negation,
    sizeof_
}

MutateKind[] mutations(MutationPoint mp) {
    import std.traits : EnumMembers;

    final switch (mp.kind) with (MutateKind) {
    case ValueKind.lvalue:
        return [EnumMembers!MutateKind];
    case ValueKind.unknown:
    case ValueKind.rvalue:
    case ValueKind.xvalue:
    case ValueKind.glvalue:
        return [preInc, preDec, address, indirection, positive, negative,
            complement, negation, sizeof_];
    }
}

string mutate(string expr, MutateKind kind) {
    final switch (kind) with (MutateKind) {
    case preInc:
        return format("++%s", expr);
    case preDec:
        return format("--%s", expr);
    case postInc:
        return format("%s++", expr);
    case postDec:
        return format("%s--", expr);
    case address:
        return format("&%s", expr);
    case indirection:
        return format("*%s", expr);
    case positive:
        return format("+%s", expr);
    case negative:
        return format("-%s", expr);
    case complement:
        return format("~%s", expr);
    case negation:
        return format("!%s", expr);
    case sizeof_:
        return format("sizeof(%s)", expr);
    }
}

size_t randomMutationPoint(const Nullable!size_t point, const size_t total_mutation_points) {
    if (point.isNull || point >= total_mutation_points)
        return 0;
    return point.get;
}
