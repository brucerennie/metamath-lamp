open MM_context
open MM_proof_tree

let rec buildSyntaxTreeInner = (
    ~proofNode:proofNode,
    ~ctxIntToAsrtInt:int=>int,
    ~asrtIntToSym:int=>string,
    ~ctxHypLabelAndAsrtVarToAsrtHypLabel:(string,int)=>option<string>,
    ~idSeq:unit=>int,
):result<MM_syntax_tree.syntaxTreeNode,string> => {
    let expr = proofNode->pnGetExpr
    switch proofNode->pnGetProof {
        | None => Error("Cannot build a syntax tree from a node without proof.")
        | Some(AssertionWithErr(_)) => Error("Cannot build a syntax tree from a node with an AssertionWithErr proof.")
        | Some(Hypothesis({label})) => {
            let maxI = expr->Array.length - 1
            let children = Expln_utils_common.createArray(maxI)
            let parentNodeId = idSeq()
            for i in 1 to maxI {
                let symInt = expr->Array.getUnsafe(i)->ctxIntToAsrtInt
                children[i-1] = MM_syntax_tree.Symbol({
                    id: idSeq(),
                    symInt,
                    sym: symInt->asrtIntToSym,
                    isVar: symInt >= 0,
                    color: None,
                })
            }
            let label = if (children->Array.length == 1) {
                switch children->Array.getUnsafe(0) {
                    | Subtree(_) => label
                    | Symbol({isVar, symInt}) => {
                        if (isVar) {
                            ctxHypLabelAndAsrtVarToAsrtHypLabel(label, symInt)->Option.getOr(label)
                        } else {
                            label
                        }
                    }
                }
            } else {
                label
            }
            Ok({
                id: parentNodeId,
                typ:expr->Array.getUnsafe(0),
                label,
                children,
                height:-1,
            })
        }
        | Some(VarType) => {
            // VarType is used only for new variables, but syntax proofs don't introduce new variables.
            // So, this case should not happen in this method
            Exn.raiseError("buildSyntaxTreeInner.VarType")
        }
        | Some(Assertion({args, frame})) => {
            let this:MM_syntax_tree.syntaxTreeNode = {
                id: idSeq(),
                typ:frame.asrt->Array.getUnsafe(0),
                label:frame.label,
                children: Expln_utils_common.createArray(frame.asrt->Array.length - 1),
                height:-1,
            }
            let err = ref(None)
            frame.asrt->Array.forEachWithIndex((s,i) => {
                if (i > 0 && err.contents->Belt_Option.isNone) {
                    if (s < 0) {
                        let symInt = s->ctxIntToAsrtInt
                        this.children[i-1] = MM_syntax_tree.Symbol({
                            id: idSeq(),
                            symInt,
                            sym: symInt->asrtIntToSym,
                            isVar: false,
                            color: None,
                        })
                    } else {
                        switch buildSyntaxTreeInner(
                            ~proofNode=args->Array.getUnsafe(frame.varHyps->Array.getUnsafe(s)),
                            ~ctxIntToAsrtInt, ~asrtIntToSym, 
                            ~ctxHypLabelAndAsrtVarToAsrtHypLabel, ~idSeq,
                        ) {
                            | Error(msg) => err := Some(Error(msg))
                            | Ok(subtree) => this.children[i-1] = Subtree(subtree)
                        }
                        
                    }
                }
            })
            switch err.contents {
                | Some(err) => err
                | None => Ok(this)
            }
        }
    }
}

let buildSyntaxTree = (
    ~proofNode:proofNode,
    ~ctxIntToAsrtInt:int=>int,
    ~asrtIntToSym:int=>string,
    ~ctxHypLabelAndAsrtVarToAsrtHypLabel:(string,int)=>option<string>,
):result<MM_syntax_tree.syntaxTreeNode,string> => {
    let lastId = ref(-1)
    let idSeq = () => {
        lastId := lastId.contents + 1
        lastId.contents
    }
    buildSyntaxTreeInner(
        ~proofNode, ~ctxIntToAsrtInt, ~asrtIntToSym, ~ctxHypLabelAndAsrtVarToAsrtHypLabel, ~idSeq, 
    )
}

type sym =
    | Const(int)
    | CtxVar(int)
    | AsrtVar(int)

let symEq = (a,b) => {
    switch a {
        | Const(a) => {
            switch b {
                | Const(b) => a == b
                | CtxVar(_) => false
                | AsrtVar(_) => false
            }
        }
        | CtxVar(a) => {
            switch b {
                | Const(_) => false
                | CtxVar(b) => a == b
                | AsrtVar(_) => false
            }
        }
        | AsrtVar(a) => {
            switch b {
                | Const(_) => false
                | CtxVar(_) => false
                | AsrtVar(b) => a == b
            }
        }
    }
}

let arrSymEq = (a:array<sym>,b:array<sym>):bool => {
    a->Array.length == b->Array.length
        && a->Array.everyWithIndex((sa,i) => sa->symEq(b->Array.getUnsafe(i)))
}

let symToInt = (sym:sym):int => {
    switch sym {
        | Const(i) | CtxVar(i) | AsrtVar(i) => i
    }
}

module SymHash = Belt.Id.MakeHashableU({
    type t = sym
    let hash = var => {
        switch var {
            | Const(i) | CtxVar(i) | AsrtVar(i) => i
        }
    }
    let eq = symEq
})

type unifSubs = {
    subs: Belt_HashMap.t<sym,array<sym>,SymHash.identity>,
    newDisj: array<(sym,sym)>,
}

let unifSubsMake = () => {
    {
        subs:Belt_HashMap.make(~hintSize=16, ~id=module(SymHash)),
        newDisj:[],
    }
}
let unifSubsGet = (unifSubs,sym) => unifSubs.subs->Belt_HashMap.get(sym)
let unifSubsSize = unifSubs => unifSubs.subs->Belt_HashMap.size
let unifSubsReset = unifSubs => {
    unifSubs.subs->Belt_HashMap.clear
    unifSubs.newDisj->Expln_utils_common.clearArray
}

let substituteInPlace = (expr:array<sym>, e:sym, subExpr:array<sym>):unit => {
    let i = ref(0)
    while (i.contents < expr->Array.length) {
        if (expr->Array.getUnsafe(i.contents)->symEq(e)) {
            expr->Array.splice(~start=i.contents, ~remove=1, ~insert=subExpr)
            i := i.contents + subExpr->Array.length
        } else {
            i := i.contents + 1
        }
    }
}

let applySubsInPlace = (expr:array<sym>, unifSubs:unifSubs):unit => {
    unifSubs.subs->Belt_HashMap.forEachU((v, subExpr) => substituteInPlace(expr, v, subExpr))
}

let assignSubs = (foundSubs:unifSubs, var:sym, expr:array<sym>):bool => {
    if (expr->Array.some(symEq(_, var))) {
        false
    } else {
        applySubsInPlace(expr, foundSubs)
        switch foundSubs.subs->Belt_HashMap.get(var) {
            | Some(existingExpr) => arrSymEq(expr, existingExpr)
            | None => {
                foundSubs.subs->Belt_HashMap.set(var, expr)
                foundSubs.subs->Belt_HashMap.forEachU((_, expr) => applySubsInPlace(expr, foundSubs))
                true
            }
        }
    }
}

let rec getAllSymbols = (syntaxTreeNode:MM_syntax_tree.syntaxTreeNode, ~intToVar:int=>sym):array<sym> => {
    syntaxTreeNode.children->Expln_utils_common.arrFlatMap(ch => {
        switch ch {
            | Subtree(syntaxTreeNode) => getAllSymbols(syntaxTreeNode, ~intToVar)
            | Symbol({symInt}) => if (symInt < 0) {[Const(symInt)]} else {[intToVar(symInt)]}
        }
    })
}

let disjForEach = (
    ~isAsrt:bool, ~ctxDisj:disjMutable, ~asrtDisj:Belt_MapInt.t<Belt_SetInt.t>, consumer:(int,int)=>unit
) => {
    if (isAsrt) {
        asrtDisj->disjImmForEach(consumer)
    } else {
        ctxDisj->disjForEach(consumer)
    }
}

let verifyDisjoints = (
    ~unifSubs:unifSubs, 
    ~isAsrt:bool,
    ~ctxDisj:disjMutable, 
    ~asrtDisj:Belt_MapInt.t<Belt_SetInt.t>,
    ~isDisj:(sym,sym)=>bool
):bool => {
    let continue = ref(true)
    disjForEach(~isAsrt, ~ctxDisj, ~asrtDisj, (n,m) => {
        if (continue.contents) {
            switch unifSubs->unifSubsGet(isAsrt ? AsrtVar(n) : CtxVar(n)) {
                | None => ()
                | Some(nSyms) => nSyms->Array.forEach(nSym => {
                    if (continue.contents && nSym->symToInt >= 0) {
                        switch unifSubs->unifSubsGet(isAsrt ? AsrtVar(m) : CtxVar(m)) {
                            | None => ()
                            | Some(mSyms) => mSyms->Array.forEach(mSym => {
                                if (continue.contents && mSym->symToInt >= 0) {
                                    continue := !symEq(nSym, mSym)
                                    if (continue.contents && !isDisj(nSym,mSym)) {
                                        unifSubs.newDisj->Array.push((nSym,mSym))
                                    }
                                }
                            })
                        }
                    }
                })
            }
        }
    })
    continue.contents
}

let isDisj = (a:sym, b:sym, ~ctxDisj:disjMutable, ~asrtDisj:Belt_MapInt.t<Belt_SetInt.t>):bool => {
    switch a {
        | Const(_) => false
        | CtxVar(a) => {
            switch b {
                | Const(_) => false
                | CtxVar(b) => ctxDisj->disjContains(a,b)
                | AsrtVar(_) => false
            }
        }
        | AsrtVar(a) => {
            switch b {
                | Const(_) => false
                | CtxVar(_) => false
                | AsrtVar(b) => asrtDisj->disjImmContains(a,b)
            }
        }
    }
}

let verifyAllDisjoints = (~unifSubs:unifSubs, ~ctxDisj:disjMutable, ~asrtDisj:Belt_MapInt.t<Belt_SetInt.t>):bool => {
    let isDisj = (a,b) => isDisj(a, b, ~ctxDisj, ~asrtDisj)
    verifyDisjoints( ~unifSubs, ~isAsrt=true, ~ctxDisj, ~asrtDisj, ~isDisj )
        && verifyDisjoints( ~unifSubs, ~isAsrt=false, ~ctxDisj, ~asrtDisj, ~isDisj )
}

/*
    The core idea of the unification algorithm is as per explanations by Mario Carneiro.
    https://github.com/expln/metamath-lamp/issues/77#issuecomment-1577804381
*/
let rec unifyPriv = ( 
    ~asrtDisj:Belt_MapInt.t<Belt_SetInt.t>,
    ~ctxDisj:disjMutable,
    ~expr1:MM_syntax_tree.syntaxTreeNode,
    ~isMetavar1:string=>bool,
    ~int1ToVar:int=>sym,
    ~expr2:MM_syntax_tree.syntaxTreeNode,
    ~isMetavar2:string=>bool,
    ~int2ToVar:int=>sym,
    ~foundSubs:unifSubs,
    ~continue:ref<bool>,
):unit => {
    if (expr1.typ != expr2.typ) {
        continue := false
    } else {
        switch expr1->MM_syntax_tree.isVar(isMetavar1) {
            | Some((var1,_)) => {
                continue := assignSubs(foundSubs, int1ToVar(var1), expr2->getAllSymbols(~intToVar=int2ToVar))
            }
            | None => {
                switch expr2->MM_syntax_tree.isVar(isMetavar2) {
                    | Some((var2,_)) => {
                        continue := assignSubs(foundSubs, int2ToVar(var2), expr1->getAllSymbols(~intToVar=int1ToVar))
                    }
                    | None => {
                        if (expr1.children->Array.length != expr2.children->Array.length) {
                            continue := false
                        } else {
                            let maxI = expr1.children->Array.length-1
                            let i = ref(0)
                            while (continue.contents && i.contents <= maxI) {
                                switch expr1.children->Array.getUnsafe(i.contents) {
                                    | Symbol({symInt:sym1Int}) => {
                                        switch expr2.children->Array.getUnsafe(i.contents) {
                                            | Symbol({symInt:sym2Int}) => continue := sym1Int == sym2Int
                                            | Subtree(_) => continue := false
                                        }
                                    }
                                    | Subtree(ch1) => {
                                        switch expr2.children->Array.getUnsafe(i.contents) {
                                            | Symbol(_) => continue := false
                                            | Subtree(ch2) => {
                                                unifyPriv(
                                                    ~asrtDisj, ~ctxDisj,
                                                    ~expr1=ch1, ~isMetavar1, ~int1ToVar,
                                                    ~expr2=ch2, ~isMetavar2, ~int2ToVar,
                                                    ~foundSubs, ~continue
                                                )
                                            }
                                        }
                                    }
                                } 
                                i := i.contents + 1
                            }
                        }
                    }
                }
            }
        }
    }
    continue := continue.contents && verifyAllDisjoints(~unifSubs=foundSubs, ~ctxDisj, ~asrtDisj)
}

let unify = ( 
    ~asrtDisj:Belt_MapInt.t<Belt_SetInt.t>,
    ~ctxDisj:disjMutable,
    ~asrtExpr:MM_syntax_tree.syntaxTreeNode,
    ~ctxExpr:MM_syntax_tree.syntaxTreeNode,
    ~isMetavar:string=>bool,
    ~foundSubs:unifSubs,
):bool => {
    let continue=ref(true)
    foundSubs->unifSubsReset
    unifyPriv( 
        ~asrtDisj, 
        ~ctxDisj, 
        ~expr1=asrtExpr, ~isMetavar1=_=>true, ~int1ToVar=i=>AsrtVar(i),
        ~expr2=ctxExpr, ~isMetavar2=isMetavar, ~int2ToVar=i=>CtxVar(i),
        ~foundSubs, 
        ~continue, 
    )
    if (!continue.contents) {
        continue := true
        foundSubs->unifSubsReset
        unifyPriv(
            ~asrtDisj, 
            ~ctxDisj, 
            ~expr1=ctxExpr, ~isMetavar1=isMetavar, ~int1ToVar=i=>CtxVar(i),
            ~expr2=asrtExpr, ~isMetavar2=_=>true, ~int2ToVar=i=>AsrtVar(i),
            ~foundSubs, 
            ~continue, 
        )
        continue.contents
    } else {
        true
    }
}
