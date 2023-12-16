open MM_wrk_editor

type api = (string,Js.Json.t) => Js_json.t

let apiRef:ref<option<api>> = ref(None)
let api = ():option<api> => apiRef.contents

let funcNameGetAllLabels = "editor.getAllLabels"
let funcNameProveBottomUp = "editor.proveBottomUp"
let fun = {
    "editor": {
        "getAllLabels": funcNameGetAllLabels, 
        "proveBottomUp": funcNameProveBottomUp,
    }
}

let getAllLabels = (~state:editorState):Js_json.t => {
    state.stmts->Js.Array2.map(stmt => stmt.label->Js.Json.string)->Js.Json.array
}

let labelsToExprs = (st:editorState, labels:array<string>):result<array<MM_context.expr>,string> => {
    labels->Js_array2.reduce(
        (res,label) => {
            switch res {
                | Error(_) => res
                | Ok(arr) => {
                    switch st->editorGetStmtByLabel(label) {
                        | None => Error(`Cannot find a step by label '${label}'`)
                        | Some(stmt) => {
                            switch stmt.expr {
                                | None => Error(`Internal error: the step with label '${label}' doesn't have expr.`)
                                | Some(expr) => {
                                    arr->Js_array2.push(expr)->ignore
                                    res
                                }
                            }
                        }
                    }
                }
            }
        },
        Ok([])
    )
}

type proveBottomUpApiParams = {
    delayBeforeStartMs:option<int>,
    stepToProve:string,
    debugLevel:option<int>,
    args0:array<string>,
    args1:array<string>,
    frmsToUse:option<array<string>>,
    maxSearchDepth:int,
    lengthRestrict:string,
    allowNewStmts:bool,
    allowNewVars:bool,
    allowNewDisjForExistingVars:bool,
    maxNumberOfBranches:option<int>,
}
type proverParams = {
    delayBeforeStartMs:int,
    stmtId: MM_wrk_editor.stmtId,
    debugLevel:int,
    bottomUpProverParams: MM_provers.bottomUpProverParams,
}
let proveBottomUp = (
    ~paramsJson:Js_json.t,
    ~state:editorState,
    ~showError:string=>unit,
    ~canStartProvingBottomUp:bool,
    ~startProvingBottomUp:proverParams=>unit,
):Js_json.t => {
    if (!canStartProvingBottomUp) {
        showError("Cannot start proving bottom-up because either there are syntax errors in the editor or edit is in progress.")
    } else {
        open Expln_utils_jsonParse
        let parseResult:result<proveBottomUpApiParams,string> = fromJson(paramsJson, asObj(_, d=>{
            {
                delayBeforeStartMs: d->intOpt("delayBeforeStartMs", ()),
                stepToProve: d->str("stepToProve", ()),
                debugLevel: d->intOpt("debugLevel", ()),
                args0: d->arr("args0", asStr(_, ()), ()),
                args1: d->arr("args1", asStr(_, ()), ()),
                frmsToUse: d->arrOpt("frmsToUse", asStr(_, ()), ()),
                maxSearchDepth: d->int("maxSearchDepth", ()),
                lengthRestrict: d->str("lengthRestrict", ~validator = str => {
                    switch MM_provers.lengthRestrictFromStr(str) {
                        | Some(_) => Ok(str)
                        | None => Error(`lengthRestrict must be one of: No, LessEq, Less.`)
                    }
                }, ()),
                allowNewStmts: d->bool("allowNewStmts", ()),
                allowNewVars: d->bool("allowNewVars", ()),
                allowNewDisjForExistingVars: d->bool("allowNewDisjForExistingVars", ()),
                maxNumberOfBranches: d->intOpt("maxNumberOfBranches", ()),
            }
        }, ()), ())
        switch parseResult {
            | Error(msg) => showError(msg)
            | Ok(apiParams) => {
                switch state.stmts->Js.Array2.find(stmt => stmt.label == apiParams.stepToProve) {
                    | None => showError(`Cannot find a step with label '${apiParams.stepToProve}'`)
                    | Some(stmtToProve) => {
                        switch state->labelsToExprs(apiParams.args0) {
                            | Error(msg) => showError(msg)
                            | Ok(args0) => {
                                switch state->labelsToExprs(apiParams.args1) {
                                    | Error(msg) => showError(msg)
                                    | Ok(args1) => {
                                        startProvingBottomUp({
                                            delayBeforeStartMs:
                                                apiParams.delayBeforeStartMs->Belt_Option.getWithDefault(1000),
                                            stmtId: stmtToProve.id,
                                            debugLevel: apiParams.debugLevel->Belt_Option.getWithDefault(0),
                                            bottomUpProverParams: {
                                                asrtLabel: None,
                                                args0,
                                                args1,
                                                frmsToUse: apiParams.frmsToUse,
                                                maxSearchDepth: apiParams.maxSearchDepth,
                                                lengthRestrict: 
                                                    apiParams.lengthRestrict->MM_provers.lengthRestrictFromStrExn,
                                                allowNewDisjForExistingVars: apiParams.allowNewDisjForExistingVars,
                                                allowNewStmts: apiParams.allowNewStmts,
                                                allowNewVars: apiParams.allowNewVars,
                                                maxNumberOfBranches: apiParams.maxNumberOfBranches,
                                            },
                                        })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Js.Json.null
}

let makeShowError = (funcName, showError:string=>unit):(string=>unit) => msg => {
    showError(`${funcName}: ${msg}`)
}

let makeEditorApi = (
    ~state:editorState,
    ~showError:string=>unit,
    ~canStartProvingBottomUp:bool,
    ~startProvingBottomUp:proverParams=>unit,
):api => (funcName,paramsJson) => {
    if (funcName == funcNameGetAllLabels) {
        getAllLabels(~state)
    } else if (funcName == funcNameProveBottomUp) {
        proveBottomUp(
            ~paramsJson, 
            ~state, 
            ~showError=makeShowError(funcName,showError),
            ~canStartProvingBottomUp,
            ~startProvingBottomUp,
        )
    } else {
        showError(`Unknown api function ${funcName}`)
        Js.Json.null
    }
}

let updateEditorApi = (
    ~state:editorState,
    ~showError:string=>unit,
    ~canStartProvingBottomUp:bool,
    ~startProvingBottomUp:proverParams=>unit,
):unit => {
    apiRef := Some(
        makeEditorApi(
            ~state,
            ~showError,
            ~canStartProvingBottomUp,
            ~startProvingBottomUp,
        )
    )
}