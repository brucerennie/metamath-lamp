open MM_parser
open MM_context
open MM_substitution
open MM_asrt_apply
open MM_parenCounter
open MM_proof_table
open MM_progress_tracker

type rec proofNode = {
    expr:expr,
    exprStr:option<string>, //for debug purposes
    label: option<string>,
    mutable parents: option<array<exprSource>>,
    mutable children: array<proofNode>,
    mutable proof: option<exprSource>,
    tree: proofTree
}

and exprSource =
    | ParentTree
    | VarType
    | Hypothesis({label:string})
    | Assertion({args:array<proofNode>, frame:frame})

and proofTree = {
    frms: Belt_MapString.t<frmSubsData>,
    hypsByExpr: Belt_Map.t<expr,hypothesis,ExprCmp.identity>,
    hypsByLabel: Belt_MapString.t<hypothesis>,
    ctxMaxVar:int,
    mutable maxVar:int,
    newVars: Belt_MutableSet.t<expr,ExprCmp.identity>,
    disj: disjMutable,
    parenCnt:parenCnt,
    nodes: Belt_MutableMap.t<expr,proofNode,ExprCmp.identity>,
    exprToStr: option<expr=>string>, //for debug purposes

    parentTree:option<proofTree>,
    allowParentsWithUnprovedFloatings:bool,
}

let exprSourceEq = (s1,s2) => {
    switch s1 {
        | ParentTree => {
            switch s2 {
                | ParentTree => true
                | _ => false
            }
        }
        | VarType => {
            switch s2 {
                | VarType => true
                | _ => false
            }
        }
        | Hypothesis({label:label1}) => {
            switch s2 {
                | Hypothesis({label:label2}) => label1 == label2
                | _ => false
            }
        }
        | Assertion({ args:args1, frame:frame1, }) => {
            switch s2 {
                | Assertion({ args:args2, frame:frame2, }) => {
                    frame1.label == frame2.label
                    && args1->Js.Array2.length == args2->Js.Array2.length
                    && args1->Js.Array2.everyi((arg1,idx) => exprEq(arg1.expr, args2[idx].expr))
                }
                | _ => false
            }
        }
    }
}

let ptGetFrms = tree => tree.frms
let ptGetParenCnt = tree => tree.parenCnt
let ptIsDisj = (tree, n, m) => tree.disj->disjContains(n,m)
let ptIsNewVarDef = (tree, expr) => tree.newVars->Belt_MutableSet.has(expr)

let ptMake = (
    ~frms: option<Belt_MapString.t<frmSubsData>>=?,
    ~hyps: option<Belt_MapString.t<hypothesis>>=?,
    ~maxVar: option<int>=?,
    ~disj: option<disjMutable>=?,
    ~parenCnt:option<parenCnt>=?,
    ~exprToStr: option<expr=>string>=?,

    ~parentTree:option<proofTree>=?,
    ~allowParentsWithUnprovedFloatings: bool=false,
    ()
) => {
    switch parentTree {
        | Some(parentTree) => {
            {
                frms: parentTree.frms,
                hypsByLabel: parentTree.hypsByLabel,
                hypsByExpr: parentTree.hypsByExpr,
                ctxMaxVar: parentTree.ctxMaxVar,
                maxVar: parentTree.maxVar,
                newVars: parentTree.newVars,
                disj: parentTree.disj,
                parenCnt: parentTree.parenCnt,
                nodes: Belt_MutableMap.make(~id=module(ExprCmp)),
                exprToStr: parentTree.exprToStr,

                parentTree: Some(parentTree),
                allowParentsWithUnprovedFloatings,
            }
        }
        | None => {
            switch (frms, hyps, maxVar, disj, parenCnt) {
                | (Some(frms), Some(hyps), Some(maxVar), Some(disj), Some(parenCnt)) => {
                    {
                        frms,
                        hypsByLabel: hyps,
                        hypsByExpr: hyps
                                        ->Belt_MapString.toArray
                                        ->Js_array2.map(((_,hyp)) => (hyp.expr, hyp))
                                        ->Belt_Map.fromArray(~id=module(ExprCmp)),
                        ctxMaxVar:maxVar,
                        maxVar,
                        newVars: Belt_MutableSet.make(~id=module(ExprCmp)),
                        disj,
                        parenCnt,
                        nodes: Belt_MutableMap.make(~id=module(ExprCmp)),
                        exprToStr,

                        parentTree,
                        allowParentsWithUnprovedFloatings
                    }
                }
                | _ => {
                    raise(MmException({
                        msg:`If parentTree is None then all the following parameters must be specified: ` 
                                ++ `frms, hyps, maxVar, disj, parenCnt.`
                    }))
                }
            }
        }
    }
}

let ptGetNodeByExpr = ( tree:proofTree, expr:expr ):option<proofNode> => {
    tree.nodes->Belt_MutableMap.get(expr)
}

let ptGetProvedNodeByExpr = ( tree:proofTree, expr:expr ):option<proofNode> => {
    switch tree.nodes->Belt_MutableMap.get(expr) {
        | None => None
        | Some(node) => {
            if (node.proof->Belt_Option.isSome) {
                Some(node)
            } else {
                None
            }
        }
    }
}

let ptGetHypByExpr = ( tree:proofTree, expr:expr ):option<hypothesis> => {
    tree.hypsByExpr->Belt_Map.get(expr)
}

let proofNodeGetExprStr = (node:proofNode):string => {
    switch node.exprStr {
        | Some(str) => str
        | None => node.expr->Js_array2.map(Belt_Int.toString)->Js.Array2.joinWith(" ")
    }
}

let ptMakeNode = ( 
    tree:proofTree,
    ~label:option<string>,
    ~expr:expr,
):proofNode => {
    switch tree.nodes->Belt_MutableMap.get(expr) {
        | Some(existingNode) => 
            raise(MmException({
                msg:`Creation of a new node was requested, ` 
                    ++ `but a node with the same expression already exists '${existingNode->proofNodeGetExprStr}'.`
            }))
        | None => {
            let node = {
                label,
                expr,
                exprStr: tree.exprToStr->Belt.Option.map(f => f(expr)),
                parents: None,
                proof: None,
                children: [],
                tree,
            }
            tree.nodes->Belt_MutableMap.set(expr, node)->ignore
            node
        }
    }
}

let esIsProved = (exprSrc:exprSource): bool => {
    switch exprSrc {
        | ParentTree | VarType | Hypothesis(_) => true
        | Assertion({args}) => args->Js_array2.every(arg => arg.proof->Belt_Option.isSome)
    }
}

let pnGetProofFromParents = (node):option<exprSource> => {
    switch node.parents {
        | None => None
        | Some(parents) => parents->Js_array2.find(esIsProved)
    }
}

let pnMarkProved = ( node:proofNode ):unit => {
    switch node.proof {
        | Some(_) => ()
        | None => {
            switch pnGetProofFromParents(node) {
                | None => ()
                | Some(nodeProof) => {
                    node.proof = Some(nodeProof)
                    let nodesToMarkProved = node.children->Belt_MutableQueue.fromArray
                    while (!(nodesToMarkProved->Belt_MutableQueue.isEmpty)) {
                        let curNode = nodesToMarkProved->Belt_MutableQueue.pop->Belt_Option.getExn
                        if (curNode.proof->Belt_Option.isNone) {
                            switch pnGetProofFromParents(curNode) {
                                | None => ()
                                | Some(curNodeProof) => {
                                    curNode.proof = Some(curNodeProof)
                                    curNode.children->Js_array2.forEach( nodesToMarkProved->Belt_MutableQueue.add )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

let pnAddChild = (node, child): unit => {
    if (!exprEq(node.expr, child.expr)) {
        switch node.children->Js.Array2.find(existingChild => exprEq(existingChild.expr,child.expr)) {
            | None => node.children->Js_array2.push(child)->ignore
            | Some(_) => ()
        }
    }
}

let pnGetLabel = node => node.label
let pnGetExpr = node => node.expr
let pnGetProof = node => node.proof
let pnGetParents = node => node.parents

let pnAddParent = (node:proofNode, parent:exprSource):unit => {
    switch node.proof {
        | Some(_) => ()
        | None => {
            if (!(node.tree.allowParentsWithUnprovedFloatings)) {
                switch parent {
                    | ParentTree | VarType | Hypothesis(_) => ()
                    | Assertion({args, frame}) => {
                        switch frame.hyps->Js_array2.findi((hyp,i) => hyp.typ == F && args[i].proof->Belt_Option.isNone) {
                            | Some(_) =>
                                raise(MmException({
                                    msg:`Cannot add a parent node with an unproved floating hypothesis.`
                                }))
                            | None => ()
                        }
                    }
                }
            }
            let newParentWasAdded = ref(false)
            switch node.parents {
                | None => {
                    node.parents = Some([parent])
                    newParentWasAdded.contents = true
                }
                | Some(parents) => {
                    switch parents->Js_array2.find(par => exprSourceEq(par, parent)) {
                        | Some(existingParent) => {
                            if (esIsProved(existingParent)) {
                                raise(MmException({
                                    msg:`Unexpected: an unproved node '${proofNodeGetExprStr(node)}' has a proved parent.`
                                }))
                            }
                        }
                        | None => {
                            parents->Js_array2.push(parent)->ignore
                            newParentWasAdded.contents = true
                        }
                    }
                }
            }
            if (newParentWasAdded.contents) {
                switch parent {
                    | ParentTree | VarType | Hypothesis(_) => ()
                    | Assertion({args}) => args->Js_array2.forEach(pnAddChild(_, node))
                }
                if (esIsProved(parent)) {
                    pnMarkProved(node)
                }
            }
        }
    }
}

// let moveProofToTargetTree = rootNode => {
//     let targetTree = rootNode.tree
//     let nodesToMove = Belt_MutableQueue.make()
//     nodesToMove->Belt_MutableQueue.add(rootNode)
//     while (!(nodesToMove->Belt_MutableQueue.isEmpty)) {
//         let curNode = nodesToMove->Belt_MutableQueue.pop()->Belt.Option.getExn
//         if (curNode === rootNode || curNode.tree !== targetTree) {
//             curNode.tree = targetTree
//             curNode.parents = Some([])
//             switch curNode.proof {
//                 | None => raise(MmException({msg:`each node must be proved in moveProofToTargetTree().`}))
//                 | Some(proof) => {
//                     switch proof {
//                         | ParentTree => {
//                             switch targetTree.nodes->Belt_MutableMap.get()
//                         }
//                     }
//                 }
//             }
//         }
//     }
//     switch rootNode.proof {
//         | None => raise(MmException({msg:`rootNode must be proved in moveProofToNodesTree().`}))
//         | Some(proof) => {
            
//         }
//     }
// }

let pnCreateProofTable = (node:proofNode):proofTable => {
    let processedExprs = Belt_MutableSet.make(~id = module(ExprCmp))
    let exprToIdx = Belt_MutableMap.make(~id = module(ExprCmp))
    let tbl = []
    Expln_utils_data.traverseTree(
        (),
        node,
        (_,n) => {
            switch n.proof {
                | None => raise(MmException({msg:`Cannot create proofTable from an unproved proofNode [1].`}))
                | Some(ParentTree) => raise(MmException({msg:`ParentTree is not supported in createProofTable [1].`}))
                | Some(VarType) => raise(MmException({msg:`VarType is not supported in createProofTable [1].`}))
                | Some(Hypothesis(_)) => None
                | Some(Assertion({args})) => {
                    if (processedExprs->Belt_MutableSet.has(n.expr)) {
                        None
                    } else {
                        Some(args)
                    }
                }
            }
        },
        ~process = (_, n) => {
            switch n.proof {
                | None => raise(MmException({msg:`Cannot create proofTable from an unproved proofNode [2].`}))
                | Some(VarType) => raise(MmException({msg:`VarType is not supported in createProofTable [2].`}))
                | Some(ParentTree) => raise(MmException({msg:`ParentTree is not supported in createProofTable [2].`}))
                | Some(Hypothesis({label})) => {
                    if (exprToIdx->Belt_MutableMap.get(n.expr)->Belt_Option.isNone) {
                        let idx = tbl->Js_array2.push({proof:Hypothesis({label:label}), expr:n.expr})-1
                        exprToIdx->Belt_MutableMap.set(n.expr,idx)
                    }
                }
                | Some(Assertion(_)) => ()
            }
            None
        },
        ~postProcess = (_, n) => {
            switch n.proof {
                | None => raise(MmException({msg:`Cannot create proofTable from an unproved proofNode [3].`}))
                | Some(VarType) => raise(MmException({msg:`VarType is not supported in createProofTable [3].`}))
                | Some(ParentTree) => raise(MmException({msg:`ParentTree is not supported in createProofTable [3].`}))
                | Some(Hypothesis(_)) => ()
                | Some(Assertion({args,frame})) => {
                    if (exprToIdx->Belt_MutableMap.get(n.expr)->Belt_Option.isNone) {
                        let idx = tbl->Js_array2.push({
                            proof:Assertion({
                                label:frame.label,
                                args: args->Js_array2.map(n => {
                                    exprToIdx->Belt_MutableMap.get(n.expr)->Belt_Option.getWithDefault(-1)
                                })
                            }),
                            expr:n.expr
                        })-1
                        exprToIdx->Belt_MutableMap.set(n.expr,idx)
                    }
                }
            }
            None
        },
        ()
    )->ignore
    tbl
}