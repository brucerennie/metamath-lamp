open Expln_test
open MM_int_test_utils
open MM_int_test_editor_methods
open MM_wrk_frag_transform
open MM_context
open Common

let rec extractResult = (reactElemDto:{..}):option<string> => {
    switch reactElemDto["cmp"]->Js.Nullable.toOption {
        | Some("ApplyButtons") => reactElemDto["result"]->Js.Nullable.toOption
        | _ => {
            switch reactElemDto["children"]->Js.Nullable.toOption {
                | Some(children) => {
                    children
                        ->Js_array2.filter(child => child->Js.Nullable.toOption->Belt_Option.isSome)
                        ->Js_array2.map(child => child->Js.Nullable.toOption->Belt_Option.getExn)
                        ->Js_array2.reduce(
                            (res,child) => {
                                switch res {
                                    | Some(_) => res
                                    | None => extractResult(child)
                                }
                            },
                            None
                        )
                }
                | None => None
            }
        }
    }
}

let testTransform = (
    ~editorState:MM_wrk_editor.editorState,
    ~selectedFragment:string,
    ~transformName:string,
    ~prepareState:fragmentTransformState => fragmentTransformState,
    ~expectedResult:string,
):unit => {
    let wrkCtx = editorState.wrkCtx->Belt.Option.getExn
    let syntaxTree = MM_wrk_editor.textToSyntaxTree(
        ~wrkCtx,
        ~syms=[selectedFragment->getSpaceSeparatedValuesAsArray],
        ~syntaxTypes=["wff", "class", "setvar"]->Js.Array2.map(wrkCtx->ctxSymToIntExn),
        ~frms=editorState.frms,
        ~frameRestrict=editorState.settings.allowedFrms.inSyntax,
        ~parenCnt=editorState.parenCnt,
        ~lastSyntaxType=None,
        ~onLastSyntaxTypeChange=_=>(),
    )
    let syntaxTreeNode = switch syntaxTree {
        | Ok([Ok(syntaxTreeNode)]) => syntaxTreeNode
        | Error(msg) => Js.Exn.raiseError(`[error-1] ${msg}; when building a syntax tree for '${selectedFragment}'`)
        | Ok([Error(msg)]) => Js.Exn.raiseError(`[error-2] ${msg}; when building a syntax tree for '${selectedFragment}'`)
        | _ => Js.Exn.raiseError(`[error-3] when building a syntax tree for '${selectedFragment}'`)
    }
    let selection = syntaxTreeToSelection(Subtree(syntaxTreeNode))
    let param = {"selection":selection}
    let allTransforms = arrStrToFragTransforms([MM_frag_transform_default_script.fragmentTransformsDefaultScript])->Belt_Result.getExn
    let filteredTransforms = allTransforms->Js.Array2.filter(tr => tr.displayName(param) == transformName)
    assertEqMsg(filteredTransforms->Js.Array2.length, 1, "filteredTransforms->Js.Array2.length")
    let transform = filteredTransforms[0]
    assertEqMsg(transform.canApply(param), true, "transform.canApply(param)")

    let initState = transform.createInitialState(param)

    let elemDto = transform.renderDialog( { "selection":selection, "state":prepareState(initState), "setState":_=>() } )
    assertEq(
        elemDto->reactElemDtoToObj->extractResult->Belt.Option.map(str => {
            str->getSpaceSeparatedValuesAsArray->Js.Array2.joinWith(" ")
        }), 
        Some(expectedResult)
    )
}

let state = objToFragmentTransformState
external fromState: fragmentTransformState => {..} = "%identity"

describe("MM_wrk_editor integration tests: MM_wrk_frag_transform", _ => {
    it("Insert: X => ( X + A )", _ => {
        setTestDataDir("MM_wrk_frag_transform")
        let editorState = createEditorState( ~mmFilePath=setMmPath, ~stopBefore="mathbox", ~debug, () )
        let transformName = "Insert: X => ( X + A )"
        let prepareState = params => {
            st => state({
                "selMatch":fromState(st)["selMatch"], 
                "twoSided":params["twoSided"], 
                "text": params["text"], 
                "right": params["right"], 
                "paren": params["paren"]
            })
        }

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x",
            ~prepareState = prepareState({"twoSided":false, "text": "", "right": false, "paren": "no parentheses"}),
            ~expectedResult = "x",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x",
            ~prepareState = prepareState({"twoSided":false, "text": "1 +", "right": false, "paren": "no parentheses"}),
            ~expectedResult = "1 + x",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x",
            ~prepareState = prepareState({"twoSided":false, "text": "- 1", "right": true, "paren": "no parentheses"}),
            ~expectedResult = "x - 1",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x",
            ~prepareState = prepareState({"twoSided":false, "text": "1 +", "right": false, "paren": "[ ]"}),
            ~expectedResult = "[ 1 + x ]",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x",
            ~prepareState = prepareState({"twoSided":false, "text": "- 1", "right": true, "paren": "{ }"}),
            ~expectedResult = "{ x - 1 }",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x + y",
            ~prepareState = prepareState({"twoSided":false, "text": "- 1", "right": true, "paren": "{ }"}),
            ~expectedResult = "{ x + y - 1 }",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x = y",
            ~prepareState = prepareState({"twoSided":true, "text": "", "right": false, "paren": "no parentheses"}),
            ~expectedResult = "x = y",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x = y",
            ~prepareState = prepareState({"twoSided":true, "text": "1 +", "right": false, "paren": "no parentheses"}),
            ~expectedResult = "1 + x = 1 + y",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x = y",
            ~prepareState = prepareState({"twoSided":true, "text": "- 1", "right": true, "paren": "no parentheses"}),
            ~expectedResult = "x - 1 = y - 1",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x = y",
            ~prepareState = prepareState({"twoSided":true, "text": "1 +", "right": false, "paren": "[ ]"}),
            ~expectedResult = "[ 1 + x ] = [ 1 + y ]",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x = y",
            ~prepareState = prepareState({"twoSided":true, "text": "- 1", "right": true, "paren": "{ }"}),
            ~expectedResult = "{ x - 1 } = { y - 1 }",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( x + a ) = ( y + b )",
            ~prepareState = prepareState({"twoSided":true, "text": "- 1", "right": true, "paren": "{ }"}),
            ~expectedResult = "{ ( x + a ) - 1 } = { ( y + b ) - 1 }",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ph -> ch )",
            ~prepareState = prepareState({"twoSided":true, "text": "", "right": false, "paren": "no parentheses"}),
            ~expectedResult = "( ph -> ch )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ph -> ch )",
            ~prepareState = prepareState({"twoSided":true, "text": "1 +", "right": false, "paren": "no parentheses"}),
            ~expectedResult = "( 1 + ph -> 1 + ch )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ph -> ch )",
            ~prepareState = prepareState({"twoSided":true, "text": "- 1", "right": true, "paren": "no parentheses"}),
            ~expectedResult = "( ph - 1 -> ch - 1 )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ph -> ch )",
            ~prepareState = prepareState({"twoSided":true, "text": "1 +", "right": false, "paren": "[ ]"}),
            ~expectedResult = "( [ 1 + ph ] -> [ 1 + ch ] )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ph -> ch )",
            ~prepareState = prepareState({"twoSided":true, "text": "- 1", "right": true, "paren": "{ }"}),
            ~expectedResult = "( { ph - 1 } -> { ch - 1 } )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( x = a -> y = b )",
            ~prepareState = prepareState({"twoSided":true, "text": "- 1", "right": true, "paren": "{ }"}),
            ~expectedResult = "( { x = a - 1 } -> { y = b - 1 } )",
        )
    })

    it("Elide: ( X + A ) => X", _ => {
        setTestDataDir("MM_wrk_frag_transform")
        let editorState = createEditorState( ~mmFilePath=setMmPath, ~stopBefore="mathbox", ~debug, () )
        let transformName = "Elide: ( X + A ) => X"
        let prepareState = params => {
            st => state({
                "selMatch":fromState(st)["selMatch"], 
                "twoSided":params["twoSided"], 
                "keepLeft": params["keepLeft"], 
                "paren": params["paren"], 
            })
        }

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x = y",
            ~prepareState = prepareState({"twoSided": false, "keepLeft": true, "paren": "no parentheses"}),
            ~expectedResult = "x",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x = y",
            ~prepareState = prepareState({"twoSided": false, "keepLeft": false, "paren": "no parentheses"}),
            ~expectedResult = "y",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x = y",
            ~prepareState = prepareState({"twoSided": false, "keepLeft": true, "paren": "[ ]"}),
            ~expectedResult = "[ x ]",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x = y",
            ~prepareState = prepareState({"twoSided": false, "keepLeft": false, "paren": "{ }"}),
            ~expectedResult = "{ y }",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( x + a ) = ( y + b )",
            ~prepareState = prepareState({"twoSided": false, "keepLeft": false, "paren": "{ }"}),
            ~expectedResult = "{ ( y + b ) }",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ph -> ch )",
            ~prepareState = prepareState({"twoSided": false, "keepLeft": true, "paren": "no parentheses"}),
            ~expectedResult = "ph",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ph -> ch )",
            ~prepareState = prepareState({"twoSided": false, "keepLeft": false, "paren": "no parentheses"}),
            ~expectedResult = "ch",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ph -> ch )",
            ~prepareState = prepareState({"twoSided": false, "keepLeft": true, "paren": "[ ]"}),
            ~expectedResult = "[ ph ]",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ph -> ch )",
            ~prepareState = prepareState({"twoSided": false, "keepLeft": false, "paren": "{ }"}),
            ~expectedResult = "{ ch }",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( x = a -> y = b )",
            ~prepareState = prepareState({"twoSided": false, "keepLeft": false, "paren": "{ }"}),
            ~expectedResult = "{ y = b }",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( X + 1 ) = ( Y + 2 )",
            ~prepareState = prepareState({"twoSided": true, "keepLeft": false, "paren": "no parentheses"}),
            ~expectedResult = "1 = 2",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( X + 1 ) = ( Y + 2 )",
            ~prepareState = prepareState({"twoSided": true, "keepLeft": true, "paren": "no parentheses"}),
            ~expectedResult = "X = Y",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( X + 1 ) = ( Y + 2 )",
            ~prepareState = prepareState({"twoSided": true, "keepLeft": false, "paren": "[ ]"}),
            ~expectedResult = "[ 1 = 2 ]",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( X + 1 ) = ( Y + 2 )",
            ~prepareState = prepareState({"twoSided": true, "keepLeft": true, "paren": "{ }"}),
            ~expectedResult = "{ X = Y }",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( X + 1 -> Y + 2 )",
            ~prepareState = prepareState({"twoSided": true, "keepLeft": false, "paren": "no parentheses"}),
            ~expectedResult = "( 1 -> 2 )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( X + 1 -> Y + 2 )",
            ~prepareState = prepareState({"twoSided": true, "keepLeft": true, "paren": "no parentheses"}),
            ~expectedResult = "( X -> Y )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( X + 1 -> Y + 2 )",
            ~prepareState = prepareState({"twoSided": true, "keepLeft": false, "paren": "[ ]"}),
            ~expectedResult = "( [ 1 -> 2 ] )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( X + 1 -> Y + 2 )",
            ~prepareState = prepareState({"twoSided": true, "keepLeft": true, "paren": "{ }"}),
            ~expectedResult = "( { X -> Y } )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ( ph -> ps ) -> ( th -> ch ) )",
            ~prepareState = prepareState({"twoSided": true, "keepLeft": false, "paren": "no parentheses"}),
            ~expectedResult = "( ps -> ch )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ( ph -> ps ) -> ( th -> ch ) )",
            ~prepareState = prepareState({"twoSided": true, "keepLeft": true, "paren": "no parentheses"}),
            ~expectedResult = "( ph -> th )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ( ph -> ps ) -> ( th -> ch ) )",
            ~prepareState = prepareState({"twoSided": true, "keepLeft": false, "paren": "[ ]"}),
            ~expectedResult = "( [ ps -> ch ] )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ( ph -> ps ) -> ( th -> ch ) )",
            ~prepareState = prepareState({"twoSided": true, "keepLeft": true, "paren": "{ }"}),
            ~expectedResult = "( { ph -> th } )",
        )
    })

    it("Swap: X = Y => Y = X", _ => {
        setTestDataDir("MM_wrk_frag_transform")
        let editorState = createEditorState( ~mmFilePath=setMmPath, ~stopBefore="mathbox", ~debug, () )
        let transformName = "Swap: X = Y => Y = X"

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "x = y",
            ~prepareState = st => st,
            ~expectedResult = "y = x",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( x + a ) = ( y + b )",
            ~prepareState = st => st,
            ~expectedResult = "( y + b ) = ( x + a )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ph -> ch )",
            ~prepareState = st => st,
            ~expectedResult = "( ch -> ph )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( x = a -> y = b )",
            ~prepareState = st => st,
            ~expectedResult = "( y = b -> x = a )",
        )
    })

    it("Associate: ( A + B ) + C => A + ( B + C )", _ => {
        setTestDataDir("MM_wrk_frag_transform")
        let editorState = createEditorState( ~mmFilePath=setMmPath, ~stopBefore="mathbox", ~debug, () )
        let transformName = "Associate: ( A + B ) + C => A + ( B + C )"
        let prepareState = params => {
            st => state({
                "selMatch":fromState(st)["selMatch"], 
                "right":params["right"], 
            })
        }

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( a + b ) + c",
            ~prepareState = st => st,
            ~expectedResult = "a + ( b + c )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "a + ( b + c )",
            ~prepareState = st => st,
            ~expectedResult = "( a + b ) + c",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( a + b ) + ( c + d )",
            ~prepareState = prepareState({"right":false}),
            ~expectedResult = "( ( a + b ) + c ) + d",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( a + b ) + ( c + d )",
            ~prepareState = prepareState({"right":true}),
            ~expectedResult = "a + ( b + ( c + d ) )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ( a + b ) + c )",
            ~prepareState = st => st,
            ~expectedResult = "( a + ( b + c ) )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( a + ( b + c ) )",
            ~prepareState = st => st,
            ~expectedResult = "( ( a + b ) + c )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ( a + b ) + ( c + d ) )",
            ~prepareState = prepareState({"right":false}),
            ~expectedResult = "( ( ( a + b ) + c ) + d )",
        )

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( ( a + b ) + ( c + d ) )",
            ~prepareState = prepareState({"right":true}),
            ~expectedResult = "( a + ( b + ( c + d ) ) )",
        )
    })

    it("Replace", _ => {
        setTestDataDir("MM_wrk_frag_transform")
        let editorState = createEditorState( ~mmFilePath=setMmPath, ~stopBefore="mathbox", ~debug, () )
        let transformName = "Replace"
        let prepareState = params => {
            st => state({
                "text":params["text"], 
            })
        }

        testTransform( ~editorState, ~transformName,
            ~selectedFragment = "( 6 + 1 )",
            ~prepareState = prepareState({"text":"7"}),
            ~expectedResult = "7",
        )
    })
})