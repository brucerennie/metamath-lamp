open Expln_test
open MM_parser
open MM_context
open MM_provers
open MM_substitution
open Common
open MM_proof_tree
open Expln_utils_common

let mmFilePath = "./src/metamath/test/resources/set._mm"

let getCurrMillis = () => Js.Date.make()->Js.Date.getTime
let durationToSeconds = (start,end):int => ((end -. start) /. 1000.0)->Belt_Float.toInt
let durationToSecondsStr = (start,end):string => durationToSeconds(start,end)->Belt.Int.toString
let compareExprBySize = comparatorBy(Js_array2.length)

let log = msg => Js.Console.log(`${currTimeStr()} ${msg}`)

describe("proveSyntaxTypes", _ => {

    it("finds syntax proofs for each assertion in set.mm", _ => {
        //given
        let mmFileText = Expln_utils_files.readStringFromFile(mmFilePath)
        let (ast, _) = parseMmFile(~mmFileContent=mmFileText, ())

        let ctx = ast->loadContext(
            ~descrRegexToDisc = "\\(New usage is discouraged\\.\\)"->strToRegex->Belt_Result.getExn,
            // ~stopBefore="mathbox",
            // ~debug=true,
            ()
        )
        let parens = "( ) [ ] { } [. ]. [_ ]_ <. >. <\" \"> << >> [s ]s (. ). (( ))"
        let ctx = ctx->ctxOptimizeForProver(~parens, ())
        ctx->openChildContext
        let (_,syntaxTypes) = MM_wrk_pre_ctx_data.findTypes(ctx)

        let typToLocVars: Belt_HashMapInt.t<array<int>> = Belt_HashMapInt.make(~hintSize=4)
        let typToNextLocVarIdx: Belt_HashMapInt.t<int> = Belt_HashMapInt.make(~hintSize=16)

        let createNewVar = (typ:int):int => {
            @warning("-8")
            let [label] = generateNewLabels( ~ctx=ctx, ~prefix="locVar", ~amount=1, (), )
            @warning("-8")
            let [varName] = generateNewVarNames( ~ctx=ctx, ~types=[typ], () )
            ctx->applySingleStmt( Var({symbols:[varName]}), () )
            ctx->applySingleStmt( Floating({label, expr:[ctx->ctxIntToSymExn(typ), varName]}), () )
            ctx->ctxSymToIntExn(varName)
        }

        let getCtxLocVar = (typ:int):int => {
            switch typToLocVars->Belt_HashMapInt.get(typ) {
                | None => {
                    let newVar = createNewVar(typ)
                    typToLocVars->Belt_HashMapInt.set(typ,[newVar])
                    typToNextLocVarIdx->Belt_HashMapInt.set(typ,1)
                    newVar
                }
                | Some(locVars) => {
                    switch typToNextLocVarIdx->Belt_HashMapInt.get(typ) {
                        | None => Js.Exn.raiseError("None == typToNextLocVarIdx->Belt_HashMapInt.get(typ)")
                        | Some(idx) => {
                            if (locVars->Js_array2.length <= idx) {
                                let newVar = createNewVar(typ)
                                locVars->Js_array2.push(newVar)->ignore
                                typToNextLocVarIdx->Belt_HashMapInt.set(typ,locVars->Js_array2.length)
                                newVar
                            } else {
                                let existingVar = locVars[idx]
                                typToNextLocVarIdx->Belt_HashMapInt.set(typ,idx+1)
                                existingVar
                            }
                        }
                    }
                }
            }
        }

        let resetCtxLocVars = () => {
            typToNextLocVarIdx->Belt_HashMapInt.keysToArray->Js.Array2.forEach(typ => {
                typToNextLocVarIdx->Belt_HashMapInt.set(typ,0)
            })
        }

        let asrtVarsToLocVars = (asrtVarTypes:array<int>):array<int> => {
            asrtVarTypes->Js_array2.map(getCtxLocVar)
        }

        let asrtIntToCtxInt = (i:int,asrtVarToLocVar:array<int>):int => {
            if (i < 0) {
                i
            } else {
                asrtVarToLocVar[i]
            }
        }

        let maxNumOfVars = ref(0)

        let asrtExprs:array<expr> = []
        ctx->forEachFrame(frame => {
            resetCtxLocVars()
            let asrtVarToLocVar = asrtVarsToLocVars(frame.varTypes)
            asrtExprs->Js.Array2.push(
                frame.asrt->Js_array2.map(asrtIntToCtxInt(_,asrtVarToLocVar))
            )->ignore
            if (maxNumOfVars.contents < frame.numOfVars) {
                maxNumOfVars := frame.numOfVars
            }
            None
        })->ignore
        asrtExprs->Js.Array2.sortInPlaceWith(compareExprBySize->comparatorInverse)->ignore

        Js.Console.log2(`maxNumOfVars`, maxNumOfVars.contents)

        // let asrtExprStr = asrtExprs->Js.Array2.map(ctx->ctxIntsToStrExn)->Js.Array2.joinWith("\n")
        // Expln_utils_files.writeStringToFile(asrtExprStr, "./asrtExprStr.txt")

        let numOfExpr = asrtExprs->Js.Array2.length
        let from = 0
        let to_ = from + numOfExpr
        let exprsToSyntaxProve = asrtExprs->Js.Array2.slice(~start=from,~end_=to_)
            ->Js_array2.map(expr => expr->Js_array2.sliceFrom(1))
        let frms = prepareFrmSubsData(~ctx, ())
        let parenCnt = MM_provers.makeParenCnt(~ctx, ~parens)

        let totalSize =exprsToSyntaxProve->Js_array2.reduce(
            (size,expr) => {
                size + expr->Js_array2.length
            },
            0
        )
        Js.Console.log2(`totalSize`, totalSize)

        let startMs = getCurrMillis()
        let lastPct = ref(startMs)
        log(`started proving syntax (from = ${from->Belt.Int.toString}, to = ${(to_-1)->Belt.Int.toString})`)

        //when
        let proofTree = proveSyntaxTypes(
            ~wrkCtx=ctx,
            ~frms,
            ~frameRestrict={
                useDisc:true,
                useDepr:true,
                useTranDepr:true,
            },
            ~parenCnt,
            ~exprs=exprsToSyntaxProve,
            ~syntaxTypes,
            ~onProgress=pct=>{
                let currMs = getCurrMillis()
                log(`proving syntax: ${pct->floatToPctStr} - ${durationToSecondsStr(lastPct.contents, currMs)} sec`)
                lastPct := currMs
            },
            ()
        )

        //then
        let endMs = getCurrMillis()
        log(`Overall duration (sec): ${durationToSecondsStr(startMs, endMs)}` )

        // Expln_utils_files.writeStringToFile(proofTree->ptPrintStats, "./unprovedNodes.txt")

        let unprovedAsrtExprs = asrtExprs
            ->Js.Array2.filter(expr => proofTree->ptGetSyntaxProof(expr->Js_array2.sliceFrom(1))->Belt_Option.isNone)
        // let unprovedAsrtExprStr = unprovedAsrtExprs->Js.Array2.map(ctx->ctxIntsToStrExn)->Js.Array2.joinWith("\n")
        // Expln_utils_files.writeStringToFile(unprovedAsrtExprStr, "./unprovedAsrtExprStr.txt")
        assertEqMsg(unprovedAsrtExprs->Js.Array2.length, 0, "unprovedAsrtExprs->Js.Array2.length = 0")

    })
})