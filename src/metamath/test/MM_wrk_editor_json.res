open MM_wrk_editor
open MM_parenCounter
open MM_wrk_pre_ctx_data

type userStmtLocStor = {
    label: string,
    typ: string,
    isGoal: bool,
    isBkm:bool,
    cont: string,
    jstfText: string,
}

type editorStateLocStor = {
    srcs: array<mmCtxSrcDto>,
    descr: string,
    varsText: string,
    disjText: string,
    stmts: array<userStmtLocStor>,
}

let userStmtLocStorToUserStmt = (userStmtLocStor:userStmtLocStor):userStmt => {
    {
        id: "",

        label: userStmtLocStor.label,
        labelEditMode: false,
        typ: userStmtTypeFromStr(userStmtLocStor.typ),
        typEditMode: false,
        isGoal: userStmtLocStor.isGoal,
        isBkm: userStmtLocStor.isBkm,
        cont: strToCont(userStmtLocStor.cont),
        contEditMode: false,
        isDuplicated: false,

        jstfText: userStmtLocStor.jstfText,
        jstfEditMode: false,

        stmtErr: None,

        expr: None,
        jstf: None,
        proofTreeDto: None,
        src: None,
        proof: None,
        proofStatus: None,
        unifErr: None,
        syntaxErr: None,
    }
}

let createInitialEditorState = (
    ~preCtxData:preCtxData, 
    ~stateLocStor:option<editorStateLocStor>,
) => {
    let st = {
        preCtxData:preCtxData,

        srcs:preCtxData.srcs,
        preCtxV:preCtxData.ctxV.ver,
        preCtx:preCtxData.ctxV.val,
        frms: MM_substitution.frmsEmpty(),
        parenCnt: parenCntMake(~parenMin=0, ~canBeFirstMin=0, ~canBeFirstMax=0, ~canBeLastMin=0, ~canBeLastMax=0),
        allTypes: [],
        syntaxTypes: [],
        parensMap:Belt_HashMapString.make(~hintSize=0),
        typeOrderInDisj:Belt_HashMapInt.make(~hintSize=0),

        descr: stateLocStor->Belt.Option.map(obj => obj.descr)->Belt.Option.getWithDefault(""),
        descrEditMode: false,

        varsText: stateLocStor->Belt.Option.map(obj => obj.varsText)->Belt.Option.getWithDefault(""),
        varsEditMode: false,
        varsErr: None,
        wrkCtxColors: Belt_HashMapString.make(~hintSize=0),

        disjText: stateLocStor->Belt.Option.map(obj => obj.disjText)->Belt.Option.getWithDefault(""),
        disjEditMode: false,
        disjErr: None,

        wrkCtx: None,

        nextStmtId: stateLocStor
            ->Belt.Option.map(stateLocStor => stateLocStor.stmts->Array.length)
            ->Belt.Option.getWithDefault(0),
        stmts: 
            stateLocStor
                ->Belt.Option.map(obj => obj.stmts->Array.mapWithIndex((stmtLocStor,i) => {
                    {
                        ...userStmtLocStorToUserStmt(stmtLocStor),
                        id: i->Belt_Int.toString
                    }
                }))
                ->Belt.Option.getWithDefault([]),
        checkedStmtIds: [],

        nextAction: None,
    }
    let st = st->setPreCtxData(preCtxData)
    st
}

let editorStateToEditorStateLocStor = (state:editorState):editorStateLocStor => {
    {
        srcs: state.srcs->Array.map(src => {...src, ast:None, allLabels:[]}),
        descr:state.descr,
        varsText: state.varsText,
        disjText: state.disjText,
        stmts: state.stmts->Array.map(stmt => {
            {
                label: stmt.label,
                typ: (stmt.typ->userStmtTypeToStr),
                isGoal: stmt.isGoal,
                isBkm: stmt.isBkm,
                cont: contToStr(stmt.cont),
                jstfText: stmt.jstfText,
            }
        }),
    }
}

let fixDisjFormat = (st:editorStateLocStor):editorStateLocStor => {
    /* 
        The fix for the issue https://github.com/expln/metamath-lamp/issues/199 introduced a breaking change.
        This function changes the old format of disjoints to the new one.
     */

    /* 
     The first step is to identify the old format. The old format doesn't contain spaces at all. No matter how a user 
     formatted disjoints manually in the editor, the MM_wrk_editor.removeUnusedVars() function got called eafter each 
     such editing and reformatted disjoints by concatenating variable names with commas. So, no space can appear in 
     the old format. In the new format, however, a space should appear at least once. Hence, absence of the space is 
     the indicator of the old format.
     */
    if (st.disjText->String.includes(" ")) {
        st
    } else {
        /* 
         To convert the old format to the new one it is enough to just replace commas with spaces. There are variable 
         names with commas, but they are unlikely to appear in exported JSONs and URLs because of the aforementioned 
         bug.
         */
        {
            ...st,
            disjText: st.disjText->String.replaceAll(",", " ")
        }
    }
}

let readEditorStateFromJsonStr = (jsonStr:string):result<editorStateLocStor,string> => {
    open Expln_utils_jsonParse
    parseJson(jsonStr, asObj(_, d=>{
        {
            srcs: d->arr("srcs", asObj(_, d=>{
                {
                    typ: d->str("typ"),
                    fileName: d->str("fileName"),
                    url: d->str("url"),
                    readInstr: d->str("readInstr"),
                    label: d->str("label"),
                    resetNestingLevel: d->bool("resetNestingLevel", ~default=()=>true),
                    ast: None,
                    allLabels: [],
                }
            }), ~default=()=>[]),
            descr: d->str("descr", ~default=()=>""),
            varsText: d->str("varsText", ~default=()=>""),
            disjText: d->str("disjText", ~default=()=>""),
            stmts: d->arr("stmts", asObj(_, d=>{
                {
                    label: d->str("label"),
                    typ: d->str("typ"),
                    isGoal: d->bool("isGoal", ~default=()=>false),
                    isBkm: d->bool("isBkm", ~default=()=>false),
                    cont: d->str("cont"),
                    jstfText: d->str("jstfText"),
                }
            }))
        }
    }))->Result.map(fixDisjFormat)
}
