open Expln_React_common
open MM_proof_tree_dto
open MM_context
open MM_unification_debug

type state = {
    expanded: bool,
    expandedSrcs: array<int>,
}

let makeInitialState = ():state => {
    {
        expanded: false,
        expandedSrcs: [],
    }
}

let toggleExpanded = st => {
    {
        ...st,
        expanded: !st.expanded
    }
}

let isExpandedSrc = (st,srcIdx) => st.expandedSrcs->Js_array2.includes(srcIdx)

let expandCollapseSrc = (st,srcIdx) => {
    if (st.expandedSrcs->Js_array2.includes(srcIdx)) {
        {
            ...st,
            expandedSrcs: st.expandedSrcs->Js.Array2.filter(i => i != srcIdx)
        }
    } else {
        {
            ...st,
            expandedSrcs: st.expandedSrcs->Js.Array2.concat([srcIdx])
        }
    }
}

let validProofIcon = 
    <span
        title="This is a valid proof"
        style=ReactDOM.Style.make(~color="green", ~fontWeight="bold", ())
    >
        {React.string("\u2713")}
    </span>

module rec ProofNodeDtoCmp: {
    @react.component
    let make: (
        ~tree: proofTreeDto,
        ~nodeIdx: int,
        ~isRootStmt: int=>bool,
        ~nodeIdxToLabel: int=>string,
        ~exprToReElem: expr=>reElem,
    ) => reElem
} = {
    @react.component
    let make = (
        ~tree: proofTreeDto,
        ~nodeIdx: int,
        ~isRootStmt: int=>bool,
        ~nodeIdxToLabel: int=>string,
        ~exprToReElem: expr=>reElem,
    ) => {
        let (state, setState) = React.useState(makeInitialState)

        let node = tree.nodes[nodeIdx]

        let actToggleExpanded = () => {
            setState(toggleExpanded)
        }

        let actToggleSrcExpanded = (srcIdx) => {
            setState(expandCollapseSrc(_, srcIdx))
        }

        let getColorForLabel = nodeIdx => {
            if(isRootStmt(nodeIdx)) {
                "black"
            } else {
                "lightgrey"
            }
        }

        let rndExpandCollapseIcon = (expand) => {
            let char = if (expand) {"\u229E"} else {"\u229F"}
            <span style=ReactDOM.Style.make(~fontSize="13px", ())>
                {React.string(char)}
            </span>
        }

        let rndCollapsedArgs = (args) => {
            <span>
                {
                    args->Js_array2.mapi((arg,i) => {
                        <span
                            key={i->Belt_Int.toString} 
                            style=ReactDOM.Style.make(~color=getColorForLabel(arg), ())
                        >
                            {React.string(nodeIdxToLabel(arg) ++ " ")}
                        </span>
                    })->React.array
                }
            </span>
        }

        let rndExpandedArgs = (args) => {
            <table>
                <tbody>
                    <tr key="c-args">
                        <td>
                            {rndCollapsedArgs(args)}
                        </td>
                    </tr>
                    {
                        if (args->Js_array2.length == 0) {
                            <tr key={"-exp"}>
                                <td>
                                    {React.string("This assertion doesn't have hypotheses.")}
                                </td>
                            </tr>
                        } else {
                            args->Js_array2.mapi((arg,argIdx) => {
                                <tr key={argIdx->Belt_Int.toString ++ "-exp"}>
                                    <td>
                                        <ProofNodeDtoCmp
                                            tree
                                            nodeIdx=arg
                                            isRootStmt
                                            nodeIdxToLabel
                                            exprToReElem
                                        />
                                    </td>
                                </tr>
                            })->React.array
                        }
                    }
                </tbody>
            </table>
        }

        let rndStatusIconForStmt = (node:proofNodeDto) => {
            <span
                title="This is proved"
                style=ReactDOM.Style.make(
                    ~color="green", 
                    ~fontWeight="bold", 
                    ~visibility=if (node.proof->Belt_Option.isSome) {"visible"} else {"hidden"},
                    ()
                )
            >
                {React.string("\u2713")}
            </span>
        }

        let rndStatusIconForSrc = (src:exprSourceDto) => {
            switch src {
                | VarType | Hypothesis(_) => validProofIcon
                | Assertion({args, err}) => {
                    switch err {
                        | None => {
                            let allArgsAreProved = args->Js_array2.every(arg => tree.nodes[arg].proof->Belt_Option.isSome)
                            if (allArgsAreProved) {
                                validProofIcon
                            } else {
                                React.null
                            }
                        }
                        | Some(_) => {
                            <span
                                title="Click to see error details"
                                style=ReactDOM.Style.make(~color="red", ~fontWeight="bold", ~cursor="pointer", ())
                            >
                                {React.string("\u2717")}
                            </span>
                        }
                    }
                }
            }
        }

        let rndSrc = (src,srcIdx) => {
            let key = srcIdx->Belt_Int.toString
            switch src {
                | VarType => {
                    <tr key>
                        <td style=ReactDOM.Style.make(~verticalAlign="top", ())> {rndStatusIconForSrc(src)} </td>
                        <td> {React.string("VarType")} </td>
                        <td> {React.null} </td>
                    </tr>
                }
                | Hypothesis({label}) => {
                    <tr key>
                        <td style=ReactDOM.Style.make(~verticalAlign="top", ())> {rndStatusIconForSrc(src)} </td>
                        <td> {React.string("Hyp " ++ label)} </td>
                        <td> {React.null} </td>
                    </tr>
                }
                | Assertion({args, label}) => {
                    <tr key>
                        <td style=ReactDOM.Style.make(~verticalAlign="top", ())> {rndStatusIconForSrc(src)} </td>
                        <td
                            onClick={_=>actToggleSrcExpanded(srcIdx)}
                            style=ReactDOM.Style.make(~cursor="pointer", ~verticalAlign="top", ())
                        >
                            {rndExpandCollapseIcon(!(state->isExpandedSrc(srcIdx)))}
                            <i>{React.string(label ++ ":")}</i>
                        </td>
                        <td>
                            {
                                if (state->isExpandedSrc(srcIdx)) {
                                    rndExpandedArgs(args)
                                } else {
                                    rndCollapsedArgs(args)
                                }
                            } 
                        </td>
                    </tr>
                }
            }
        }

        let rndSrcs = () => {
            switch node.parents {
                | None => {
                    React.string("Sources are not set.")
                }
                | Some(parents) => {
                    <table>
                        <tbody>
                            {
                                parents->Js_array2.mapi((src,srcIdx) => rndSrc(src,srcIdx))->React.array
                            }
                        </tbody>
                    </table>
                }
            }
        }

        let rndNode = () => {
            <table>
                <tbody>
                    <tr>
                        <td> {rndStatusIconForStmt(node)} </td>
                        <td
                            style=ReactDOM.Style.make(
                                ~cursor="pointer", 
                                ~color=getColorForLabel(nodeIdx), ()
                            )
                            onClick={_=>actToggleExpanded()}
                        > 
                            {rndExpandCollapseIcon(!state.expanded)}
                            {React.string(nodeIdxToLabel(nodeIdx) ++ ":")}
                        </td>
                        <td> {exprToReElem(tree.nodes[nodeIdx].expr)} </td>
                    </tr>
                    {
                        if (state.expanded) {
                            <tr>
                                <td> React.null </td>
                                <td> React.null </td>
                                <td>
                                    {rndSrcs()}
                                </td>
                            </tr>
                        } else {
                            React.null
                        }
                    }
                </tbody>
            </table>
        }

        rndNode()
    }
}

@react.component
let make = (
    ~tree: proofTreeDto,
    ~nodeIdx: int,
    ~isRootStmt: int=>bool,
    ~nodeIdxToLabel: int=>string,
    ~exprToReElem: expr=>reElem,
) => {
    <ProofNodeDtoCmp
        tree
        nodeIdx
        isRootStmt
        nodeIdxToLabel
        exprToReElem
    />
}