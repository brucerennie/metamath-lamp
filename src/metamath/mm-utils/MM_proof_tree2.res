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
}
and exprSource =
    | VarType
    | Hypothesis({label:string})
    | Assertion({ args:array<proofNode>, label:string })

type proofTree = {
    frms: Belt_MapString.t<frmSubsData>,
    hypsByExpr: Belt_Map.t<expr,hypothesis,ExprCmp.identity>,
    hypsByLabel: Belt_MapString.t<hypothesis>,
    ctxMaxVar:int,
    mutable maxVar:int,
    newVars: Belt_MutableSet.t<expr,ExprCmp.identity>,
    disj: disjMutable,
    parenCnt:parenCnt,
    rootNodes: Belt_MutableMap.t<expr,proofNode,ExprCmp.identity>,
    nodes: Belt_MutableMap.t<expr,proofNode,ExprCmp.identity>,
    exprToStr: option<expr=>string>, //for debug purposes
}

let exprSourceEq = (s1,s2) => {
    switch s1 {
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
        | Assertion({ args:args1, label:label1, }) => {
            switch s2 {
                | Assertion({ args:args2, label:label2, }) => {
                    label1 == label2
                    && args1->Js.Array2.length == args2->Js.Array2.length
                    && args1->Js.Array2.everyi((arg1,idx) => exprEq(arg1.expr, args2[idx].expr))
                }
                | _ => false
            }
        }
    }
}

let proofTreeGetFrms = tree => tree.frms
let proofTreeGetParenCnt = tree => tree.parenCnt
let proofTreeIsDisj = (tree, n, m) => tree.disj->disjContains(n,m)
let proofTreeIsNewVarDef = (tree, expr) => tree.newVars->Belt_MutableSet.has(expr)

let proofTreeMake = (
    ~frms: Belt_MapString.t<frmSubsData>,
    ~hyps: Belt_MapString.t<hypothesis>,
    ~maxVar: int,
    ~disj: disjMutable,
    ~parenCnt:parenCnt,
    ~exprToStr: option<expr=>string>,
) => {
    {
        frms,
        hypsByLabel: hyps,
        hypsByExpr: hyps->Belt_MapString.toArray->Js_array2.map(((_,hyp)) => (hyp.expr, hyp))->Belt_Map.fromArray(~id=module(ExprCmp)),
        ctxMaxVar:maxVar,
        maxVar,
        newVars: Belt_MutableSet.make(~id=module(ExprCmp)),
        disj,
        parenCnt,
        rootNodes: Belt_MutableMap.make(~id=module(ExprCmp)),
        nodes: Belt_MutableMap.make(~id=module(ExprCmp)),
        exprToStr,
    }
}

let proofTreeGetNodeByExpr = ( tree:proofTree, expr:expr ):option<proofNode> => {
    tree.nodes->Belt_MutableMap.get(expr)
}

let proofTreeGetHypByExpr = ( tree:proofTree, expr:expr ):option<hypothesis> => {
    tree.hypsByExpr->Belt_Map.get(expr)
}

let proofTreeAddRootNode = (tree, node):unit => {
    tree.rootNodes->Belt_MutableMap.set(node.expr, node)
}

let proofNodeGetExprStr = (node:proofNode):string => {
    switch node.exprStr {
        | Some(str) => str
        | None => node.expr->Js_array2.map(Belt_Int.toString)->Js.Array2.joinWith(" ")
    }
}

let proofTreeMakeNode = ( 
    tree:proofTree,
    ~label:option<string>,
    ~expr:expr,
):proofNode => {
    switch tree.nodes->Belt_MutableMap.get(expr) {
        | Some(existingNode) => 
            raise(MmException({
                msg:`Creation of a new node was requested, ` 
                    ++ `but a node with the same expr already exists '${existingNode->proofNodeGetExprStr}'.`
            }))
        | None => {
            let node = {
                label,
                expr,
                exprStr: tree.exprToStr->Belt.Option.map(f => f(expr)),
                parents: None,
                proof: None,
                children: [],
            }
            tree.nodes->Belt_MutableMap.set(expr, node)->ignore
            node
        }
    }
}

let exprSourceIsProved = (exprSrc:exprSource): bool => {
    switch exprSrc {
        | VarType | Hypothesis(_) => true
        | Assertion({args}) => args->Js_array2.every(arg => arg.proof->Belt_Option.isSome)
    }
}

let proofNodeGetProofFromParents = (node):option<exprSource> => {
    switch node.parents {
        | None => None
        | Some(parents) => parents->Js_array2.find(exprSourceIsProved)
    }
}

let proofNodeMarkProved = ( node:proofNode ):unit => {
    switch node.proof {
        | Some(_) => ()
        | None => {
            switch proofNodeGetProofFromParents(node) {
                | None => ()
                | Some(nodeProof) => {
                    node.proof = Some(nodeProof)
                    let nodesToMarkProved = node.children->Belt_MutableQueue.fromArray
                    while (!(nodesToMarkProved->Belt_MutableQueue.isEmpty)) {
                        let curNode = nodesToMarkProved->Belt_MutableQueue.pop->Belt_Option.getExn
                        if (curNode.proof->Belt_Option.isNone) {
                            switch proofNodeGetProofFromParents(curNode) {
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

let proofNodeAddChild = (node, child): unit => {
    if (!exprEq(node.expr, child.expr)) {
        switch node.children->Js.Array2.find(existingChild => exprEq(existingChild.expr,child.expr)) {
            | None => node.children->Js_array2.push(child)->ignore
            | Some(_) => ()
        }
    }
}

let proofNodeGetExpr = node => node.expr
let proofNodeGetProof = node => node.proof
let proofNodeGetParents = node => node.parents

let proofNodeAddParent = (node:proofNode, parent:exprSource, frame:option<frame>):unit => {
    switch node.proof {
        | Some(_) => ()
        | None => {
            switch parent {
                | VarType | Hypothesis(_) => ()
                | Assertion({args}) => {
                    switch frame {
                        | None => 
                            raise(MmException({
                                msg:`Cannot add a parent node derived from an assertion without a correspondig frame.`
                            }))
                        | Some(frame) => {
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
                            if (exprSourceIsProved(existingParent)) {
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
                    | VarType | Hypothesis(_) => ()
                    | Assertion({args}) => args->Js_array2.forEach(proofNodeAddChild(_, node))
                }
                if (exprSourceIsProved(parent)) {
                    proofNodeMarkProved(node)
                }
            }
        }
    }
}

let proofNodeAddNonAsrtParent = (node:proofNode, parent:exprSource):unit => {
    proofNodeAddParent(node, parent, None)
}

let proofNodeAddAsrtParent = (node:proofNode, parent:exprSource, frame:frame):unit => {
    proofNodeAddParent(node, parent, Some(frame))
}

let proofNodeCreateProofTable = (node:proofNode):proofTable => {
    let processedExprs = Belt_MutableSet.make(~id = module(ExprCmp))
    let exprToIdx = Belt_MutableMap.make(~id = module(ExprCmp))
    let tbl = []
    Expln_utils_data.traverseTree(
        (),
        node,
        (_,n) => {
            switch n.proof {
                | None => raise(MmException({msg:`Cannot create proofTable from an unproved proofNode [1].`}))
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
                | Some(Hypothesis(_)) => ()
                | Some(Assertion({args,label})) => {
                    if (exprToIdx->Belt_MutableMap.get(n.expr)->Belt_Option.isNone) {
                        let idx = tbl->Js_array2.push({
                            proof:Assertion({
                                label:label,
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