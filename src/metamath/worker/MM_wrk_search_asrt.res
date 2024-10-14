open MM_context
open Expln_utils_promise
open MM_wrk_ctx_proc
open MM_substitution
open MM_statements_dto
open MM_progress_tracker
open MM_wrk_settings

let procName = "MM_wrk_search_asrt"

type request = 
    | FindAssertions({label:string, typ:int, pattern:array<int>})

type response =
    | OnProgress(float)
    | SearchResult({found:array<stmtsDto>})

let reqToStr = req => {
    switch req {
        | FindAssertions({label, typ, pattern}) => 
            `FindAssertions(label="${label}", typ=${typ->Belt_Int.toString}, `
                ++ `pattern=[${pattern->Array.map(Belt_Int.toString(_))->Array.joinUnsafe(", ")}])`
    }
}

let respToStr = resp => {
    switch resp {
        | OnProgress(pct) => `OnProgress(pct=${pct->Belt_Float.toString})`
        | SearchResult(_) => `SearchResult`
    }
}

let frmExprMatchesConstPattern = (~frmExpr:expr, ~constPat:array<int>, ~varTypes:array<int>):bool => {
    let patLen = constPat->Array.length
    let asrtLen = frmExpr->Array.length
    let pIdx = ref(0)
    let aIdx = ref(0)
    while (pIdx.contents < patLen && aIdx.contents < asrtLen) {
        let asrtSym = frmExpr->Array.getUnsafe(aIdx.contents)
        let patSym = constPat->Array.getUnsafe(pIdx.contents)
        if (
            asrtSym < 0 && asrtSym == patSym
            || asrtSym >= 0 && varTypes->Array.getUnsafe(asrtSym) == patSym
        ) {
            pIdx.contents = pIdx.contents + 1
        }
        aIdx.contents = aIdx.contents + 1
    }
    pIdx.contents == patLen
}

let rec frmExprMatchesVarPatternRec = (
    ~frmExpr:expr, 
    ~varPat:array<int>, 
    ~constPat:array<int>,
    ~varTypes:array<int>,
    ~mapping:Belt_HashMapInt.t<int>,
    ~pIdx:int,
    ~minAIdx:int,
):bool => {
    if (pIdx == varPat->Array.length) {
        true
    } else {
        let aIdx = ref(minAIdx)
        let remainingMatches = ():bool => {
            frmExprMatchesVarPatternRec(
                ~frmExpr, 
                ~varPat, 
                ~constPat,
                ~varTypes,
                ~mapping,
                ~pIdx=pIdx+1,
                ~minAIdx=aIdx.contents+1,
            )
        }

        let found = ref(false)
        let maxAIdx = frmExpr->Array.length - (varPat->Array.length - pIdx)
        while (!found.contents && aIdx.contents <= maxAIdx) {
            let asrtSym = frmExpr->Array.getUnsafe(aIdx.contents)
            let varPatSym = varPat->Array.getUnsafe(pIdx)
            if ( asrtSym < 0 && asrtSym == varPatSym ) {
                found := remainingMatches()
            } else if ( asrtSym >= 0 && varTypes->Array.getUnsafe(asrtSym) == constPat->Array.getUnsafe(pIdx) ) {
                if ( varPatSym < 0 ) {
                    found := remainingMatches()
                } else {
                    switch mapping->Belt_HashMapInt.get(varPatSym) {
                        | None => {
                            mapping->Belt_HashMapInt.set(varPatSym, asrtSym)
                            found := remainingMatches()
                            mapping->Belt_HashMapInt.remove(varPatSym)
                        }
                        | Some(asrtVar) => {
                            if (asrtVar == asrtSym) {
                                found := remainingMatches()
                            }
                        }
                    }
                }
            }
            aIdx.contents = aIdx.contents + 1
        }
        found.contents
    }
}

let frmExprMatchesPattern = (
    ~frmExpr:array<int>, 
    ~varPat:array<int>, 
    ~constPat:array<int>,
    ~varTypes:array<int>,
    ~mapping:Belt_HashMapInt.t<int>
):bool => {
    frmExprMatchesConstPattern(~frmExpr,~constPat,~varTypes) && 
        frmExprMatchesVarPatternRec(
            ~frmExpr, 
            ~varPat, 
            ~constPat,
            ~varTypes,
            ~mapping:Belt_HashMapInt.t<int>,
            ~pIdx=0,
            ~minAIdx=0,
        )
}

let frameMatchesPattern = (
    ~frame:frame, 
    ~varPat:array<int>, 
    ~constPat:array<int>,
    ~mapping:Belt_HashMapInt.t<int>
):bool => {
    let varTypes = frame.varTypes
    frmExprMatchesPattern(~frmExpr=frame.asrt, ~varPat, ~constPat, ~varTypes, ~mapping)
        || frame.hyps->Array.reduce(false, (res, hyp) => {
            res || hyp.typ == E && frmExprMatchesPattern(~frmExpr=hyp.expr, ~varPat, ~constPat, ~varTypes, ~mapping)
        })
}

let searchAssertions = (
    ~settingsVer:int,
    ~settings:settings,
    ~preCtxVer: int,
    ~preCtx: mmContext,
    ~varsText: string,
    ~disjText: string,
    ~label:string,
    ~typ:int, 
    ~pattern:array<int>,
    ~onProgress:float=>unit,
): promise<array<stmtsDto>> => {
    promise(resolve => {
        beginWorkerInteractionUsingCtx(
            ~settingsVer,
            ~settings,
            ~preCtxVer,
            ~preCtx,
            ~varsText,
            ~disjText,
            ~procName,
            ~initialRequest = FindAssertions({label:label->String.toLowerCase, typ, pattern}),
            ~onResponse = (~resp, ~sendToWorker as _, ~endWorkerInteraction) => {
                switch resp {
                    | OnProgress(pct) => onProgress(pct)
                    | SearchResult({found}) => {
                        endWorkerInteraction()
                        resolve(found)
                    }
                }
            },
            ~enableTrace=false
        )
    })
}

let frameToStmtsDto = (
    ~wrkCtx:mmContext,
    ~frame:frame,
):stmtsDto => {
    let newDisj = disjMake()
    frame.disj->Belt_MapInt.forEach((n,ms) => {
        ms->Belt_SetInt.forEach(m => {
            newDisj->disjAddPair(n,m)
        })
    })
    let newDisjStr = []
    newDisj->disjForEachArr(disjArr => {
        newDisjStr->Array.push(frmIntsToStrExn(wrkCtx, frame, disjArr))
    })
    let stmts = []
    let argLabels = []
    frame.hyps->Array.forEach(hyp => {
        if (hyp.typ == E) {
            let argLabel = hyp.label
            argLabels->Array.push(argLabel)
            stmts->Array.push(
                {
                    label: argLabel,
                    expr:hyp.expr,
                    exprStr:frmIntsToStrExn(wrkCtx, frame, hyp.expr),
                    jstf:None,
                    isProved: false,
                }
            )
        }
    })
    stmts->Array.push(
        {
            label: frame.label,
            expr:frame.asrt,
            exprStr:frmIntsToStrExn(wrkCtx, frame, frame.asrt),
            jstf:Some({args:argLabels,label:frame.label}),
            isProved: false,
        }
    )
    {
        newVars: Belt_Array.range(0, frame.numOfVars-1),
        newVarTypes: frame.varTypes,
        newDisj,
        newDisjStr,
        stmts,
    }
}

//todo: review this function
let doSearchAssertions = (
    ~wrkCtx:mmContext,
    ~frms:frms,
    ~label:string, 
    ~typ:int, 
    ~pattern:array<int>, 
    ~onProgress:option<float=>unit>=?
):array<stmtsDto> => {
    let progressState = progressTrackerMake(~step=0.01, ~onProgress?)
    let framesProcessed = ref(0.)
    let numOfFrames = frms->frmsSize->Belt_Int.toFloat
    let varPat = pattern
    let constPat = varPat->Array.map(sym => {
        if (sym < 0) {
            sym
        } else {
            wrkCtx->getTypeOfVarExn(sym)
        }
    })
    let mapping = Belt_HashMapInt.make(~hintSize=varPat->Array.length)

    let results = []
    let framesInDeclarationOrder = frms->frmsSelect
        ->Expln_utils_common.sortInPlaceWith((a,b) => Belt_Float.fromInt(a.frame.ord - b.frame.ord))
    framesInDeclarationOrder->Array.forEach(frm => {
        let frame = frm.frame
        if (
            frame.label->String.toLowerCase->String.includes(label)
            && frame.asrt->Array.getUnsafe(0) == typ 
            && frameMatchesPattern(~frame, ~varPat, ~constPat, ~mapping)
        ) {
            results->Array.push(frameToStmtsDto( ~wrkCtx, ~frame, ))
        }

        framesProcessed.contents = framesProcessed.contents +. 1.
        progressState->progressTrackerSetCurrPct(
            framesProcessed.contents /. numOfFrames
        )
    })
    results
}

let processOnWorkerSide = (~req: request, ~sendToClient: response => unit): unit => {
    switch req {
        | FindAssertions({label, typ, pattern}) => {
            let results = doSearchAssertions(
                ~wrkCtx=getWrkCtxExn(), 
                ~frms = getWrkFrmsExn(),
                ~label, 
                ~typ, 
                ~pattern, 
                ~onProgress = pct => sendToClient(OnProgress(pct))
            )
            sendToClient(SearchResult({found:results}))
        }
    }
}