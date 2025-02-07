open MM_context
open MM_proof_table
open MM_proof_tree
open MM_unification_debug
open Common

type exprSrcDto =
    | VarType
    | Hypothesis({label:string})
    | Assertion({args:array<int>, label:string})
    | AssertionWithErr({args:array<int>, label:string, err:unifErr})

type proofNodeDbgDto = {
    exprStr:string,
}

type proofTreeDbgDto = {
    newVars: array<string>,
}

type proofNodeDto = {
    expr:expr,
    parents: array<exprSrcDto>,
    proof: option<exprSrcDto>,
    dbg:option<proofNodeDbgDto>,
}

type proofTreeDto = {
    newVars: array<expr>,
    nodes: array<proofNodeDto>,
    syntaxProofs: array<(expr,proofNodeDto)>,
    dbg: option<proofTreeDbgDto>,
}

let exprSrcToDto = (
    src:exprSrc, 
    exprToIdx:Belt_HashMap.t<expr,int,ExprHash.identity>,
):exprSrcDto => {
    let nodeToIdx = (node:proofNode):int => {
        switch exprToIdx->Belt_HashMap.get(node->pnGetExpr) {
            | None => raise(MmException({msg:`exprSrcToDto: cannot get idx by expr.`}))
            | Some(idx) => idx
        }
    }

    switch src {
        | VarType => VarType
        | Hypothesis({label}) => Hypothesis({label:label})
        | Assertion({args, frame}) => {
            Assertion({
                args: args->Array.map(nodeToIdx), 
                label: frame.label,
            })
        }
        | AssertionWithErr({args, frame, err}) => {
            AssertionWithErr({
                args: args->Array.map(nodeToIdx), 
                label: frame.label,
                err
            })
        }
    }
}

let compareSrcDtos = (a:exprSrcDto, b:exprSrcDto):float => {
    switch a {
        | VarType => {
            switch b {
                | VarType => 0.0
                | Hypothesis(_) | Assertion(_) | AssertionWithErr(_) => -1.0
            }
        }
        | Hypothesis({label:aLabel}) => {
            switch b {
                | VarType => 1.0
                | Hypothesis({label:bLabel}) => String.compare(aLabel, bLabel)
                | Assertion(_) | AssertionWithErr(_) => -1.0
            }
        }
        | Assertion({label:aLabel}) | AssertionWithErr({label:aLabel}) => {
            switch b {
                | VarType | Hypothesis(_) => 1.0
                | Assertion({label:bLabel}) | AssertionWithErr({label:bLabel}) => String.compare(aLabel, bLabel)
            }
        }
    }
}

let proofNodeToDto = (
    node:proofNode, 
    exprToIdx:Belt_HashMap.t<expr,int,ExprHash.identity>,
):proofNodeDto => {
    {
        expr:node->pnGetExpr,
        dbg:node->pnGetDbg->Belt_Option.map(dbg => {
            {
                exprStr: dbg.exprStr,
            }
        }),
        parents: node->pnGetEParents->Array.map(exprSrcToDto(_,exprToIdx))->Array.toSorted(compareSrcDtos),
        proof: node->pnGetProof->Belt.Option.map(exprSrcToDto(_,exprToIdx)),
    }
}

let collectAllExprs = (
    tree:proofTree, 
    roots:array<expr>,
):Belt_HashMap.t<expr,int,ExprHash.identity> => {
    let nodesToProcess = Belt_MutableStack.make()
    tree->ptGetAllSyntaxProofs->Array.forEach(((_,node)) => nodesToProcess->Belt_MutableStack.push(node))
    roots->Array.forEach(expr => nodesToProcess->Belt_MutableStack.push(tree->ptGetNode(expr)))
    let processedNodes = Belt_HashSet.make(~id=module(ExprHash), ~hintSize=100)
    let res = Belt_HashMap.make(~id=module(ExprHash), ~hintSize=100)

    let saveNodesFromSrc = (src:exprSrc) => {
        switch src {
            | Assertion({args}) | AssertionWithErr({args}) =>
                args->Array.forEach(arg => nodesToProcess->Belt_MutableStack.push(arg))
            | VarType | Hypothesis(_) => ()
        }
    }

    while (!(nodesToProcess->Belt_MutableStack.isEmpty)) {
        let curNode = nodesToProcess->Belt_MutableStack.pop->Belt.Option.getExn
        let curExpr = curNode->pnGetExpr
        if (!(processedNodes->Belt_HashSet.has(curExpr))) {
            processedNodes->Belt_HashSet.add(curExpr)
            res->Belt_HashMap.set(curExpr, res->Belt_HashMap.size)
            curNode->pnGetEParents->Array.forEach(saveNodesFromSrc)
            curNode->pnGetProof->Belt_Option.forEach(saveNodesFromSrc)
        }
    }
    res
}

let createSyntaxProofsDto = (
    ~tree:proofTree,
    ~exprToIdx:Belt_HashMap.t<expr,int,ExprHash.identity>,
    ~nodes:array<proofNodeDto>,
): array<(expr,proofNodeDto)> => {
    tree->ptGetAllSyntaxProofs->Array.map(((expr,proofNode)) => {
        (
            expr,
            switch exprToIdx->Belt_HashMap.get(proofNode->pnGetExpr) {
                | None => raise(MmException({msg:`Could not convert proofNode to proofNodeDto for a syntax proof.`}))
                | Some(idx) => nodes->Array.getUnsafe(idx)
            }
        )
    })
}

let proofTreeToDto = (
    tree:proofTree, 
    rootStmts:array<expr>, 
):proofTreeDto => {
    let exprToIdx = collectAllExprs(tree, rootStmts)
    let nodes = Expln_utils_common.createArray(exprToIdx->Belt_HashMap.size)
    exprToIdx->Belt_HashMap.forEach((expr,idx) => {
        nodes[idx] = proofNodeToDto(tree->ptGetNode(expr), exprToIdx)
    })

    {
        newVars: tree->ptGetCopyOfNewVars,
        nodes,
        syntaxProofs: createSyntaxProofsDto( ~tree, ~exprToIdx, ~nodes, ),
        dbg: tree->ptGetDbg->Belt_Option.map(dbg => {
            {
                newVars: dbg.newVars,
            }
        })
    }
}

let createProofTable = (
    ~tree:proofTreeDto, 
    ~root:proofNodeDto, 
    ~essentialsOnly:bool=false,
    ~ctx:option<mmContext>=?
):proofTable => {
    if (essentialsOnly && ctx->Belt_Option.isNone) {
        raise(MmException({msg:"Error in createProofTable: ctx must be set when essentialsOnly == true."}))
    }

    let filterArgs = (args:array<int>, label:string):array<int> => {
        if (essentialsOnly && args->Array.length > 0) {
            let essentialArgs = []
            (ctx->Belt_Option.getExn->getFrameExn(label)).hyps->Array.forEachWithIndex((hyp,i) => {
                if (hyp.typ == E) {
                    essentialArgs->Array.push(args->Array.getUnsafe(i))
                }
            })
            essentialArgs
        } else {
            args
        }
    }

    let exprToIdx = Belt_HashMap.make(~id = module(ExprHash), ~hintSize=64)
    let tbl = []

    let getIdxByExpr = (expr:expr):option<int> => exprToIdx->Belt_HashMap.get(expr)

    let getIdxByExprExn = (expr:expr):int => {
        switch getIdxByExpr(expr) {
            | None => raise(MmException({ msg:`Could not determine idx by expr in createProofTable().` }))
            | Some(idx) => idx
        }
    }

    let saveExprToTbl = (expr:expr,proof:exprSource):unit => {
        if (getIdxByExpr(expr)->Belt_Option.isSome) {
            raise(MmException({ msg:`getIdxByExpr(expr)->Belt_Option.isSome in createProofTable().` }))
        }
        tbl->Array.push({expr, proof})
        let idx = tbl->Array.length-1
        exprToIdx->Belt_HashMap.set(expr,idx)
    }

    Expln_utils_data.traverseTree(
        (),
        root,
        (_,n) => {
            switch n.proof {
                | None => raise(MmException({msg:`Cannot create proofTable from an unproved proofNodeDto [1].`}))
                | Some(VarType) => raise(MmException({msg:`VarType is not supported in createProofTable [1].`}))
                | Some(AssertionWithErr(_)) =>
                    raise(MmException({msg:`AssertionWithErr is not supported in createProofTable [1].`}))
                | Some(Hypothesis(_)) => None
                | Some(Assertion({args,label})) => {
                    Some(filterArgs(args,label)->Array.map(idx => tree.nodes->Array.getUnsafe(idx)))
                }
            }
        },
        ~postProcess = (_, n) => {
            switch n.proof {
                | None => raise(MmException({msg:`Cannot create proofTable from an unproved proofNodeDto [2].`}))
                | Some(VarType) => raise(MmException({msg:`VarType is not supported in createProofTable [2].`}))
                | Some(AssertionWithErr(_)) =>
                    raise(MmException({msg:`AssertionWithErr is not supported in createProofTable [2].`}))
                | Some(Hypothesis({label})) => {
                    if (getIdxByExpr(n.expr)->Belt_Option.isNone) {
                        saveExprToTbl(n.expr, Hypothesis({label:label}))
                    }
                }
                | Some(Assertion({args, label})) => {
                    if (getIdxByExpr(n.expr)->Belt_Option.isNone) {
                        saveExprToTbl(
                            n.expr, 
                            Assertion({
                                label,
                                args: filterArgs(args,label)
                                        ->Array.map(nodeIdx => getIdxByExprExn((tree.nodes->Array.getUnsafe(nodeIdx)).expr))
                            })
                        )
                    }
                }
            }
            None
        }
    )->ignore
    tbl
}
