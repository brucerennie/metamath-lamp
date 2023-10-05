open Expln_React_common
open Expln_React_Mui
open MM_react_common

type state = {
    newText: string,
}

let makeInitialState = () => {
    {
        newText: "",
    }
}

let setNewText = (_, text):state => {
    {
        newText:text
    }
}

let rndIconButton = (
    ~icon:reElem, 
    ~onClick:unit=>unit, 
    ~active:bool=true, 
    ~title:option<string>=?, 
    ~color:option<string>=Some("primary"),
    ()
) => {
    <span ?title>
        <IconButton disabled={!active} onClick={_ => onClick()} ?color> icon </IconButton>
    </span>
}

@val external window: {..} = "window"

@react.component
let make = (
    ~text:string, 
    ~editMode:bool, 
    ~onEditRequested:unit=>unit, 
    ~onEditDone:string=>unit,
    ~onEditCancel:string=>unit,
    ~editByClick:bool=true,
    ~editByAltClick:bool=false,
    ~longClickEnabled:bool=false,
    ~longClickDelayMs:int=10_000,
    ~renderer:option<string=>reElem>=?,
    ~width:int=600,
    ~fullWidth:bool=false,
    ~onHelp:option<unit=>unit>=?,
    ~onDelete:option<unit=>unit>=?,
) => {
    let (state, setState) = React.useState(_ => makeInitialState())
    let (newTextCursorPosition, setNewTextCursorPosition) = React.useState(() => None)
    let textFieldRef = React.useRef(Js.Nullable.null)

    let {
        onClick, 
        onMouseDown, onMouseUp, onMouseMove, onMouseLeave, onMouseOut,
        onTouchStart, onTouchEnd, onTouchMove, onTouchCancel, 
    } = UseLongClick.useLongClick(
        ~onClick = Some(
            if (editByClick) {
                if (editByAltClick) {
                    clickHnd2(
                        clickClbkMake(~act=onEditRequested, ()),
                        clickClbkMake(~alt=true, ~act=onEditRequested, ()),
                    )
                } else {
                    clickHnd(~act=onEditRequested, ())
                }
            } else if (editByAltClick) {
                clickHnd(~alt=true, ~act=onEditRequested, ())
            } else {
                _ => ()
            }
        ),
        ~longClickEnabled = longClickEnabled && editByAltClick,
        ~longClickDelayMs,
        ~onShortClick=Some(clickAttrs => {
            switch clickAttrs {
                | Some({alt}) => {
                    if (editByClick && !alt || editByAltClick && alt) {
                        onEditRequested()
                    }
                }
                | _ => ()
            }
        }),
        ~onLongClick=Some(onEditRequested),
    )

    React.useEffect1(() => {
        if (editMode) {
            setState(setNewText(_,text))
        }
        None
    }, [editMode])

    React.useEffect1(() => {
        switch newTextCursorPosition {
            | None => ()
            | Some(newTextCursorPosition) => {
                setNewTextCursorPosition(_ => None)
                switch textFieldRef.current->Js.Nullable.toOption {
                    | None => ()
                    | Some(domElem) => {
                        let input = ReactDOM.domElementToObj(domElem)
                        input["selectionStart"]=newTextCursorPosition
                        input["selectionEnd"]=newTextCursorPosition
                    }
                }
            }
        }
        None
    }, [newTextCursorPosition])

    let actNewTextUpdated = newText => {
        setState(setNewText(_, newText))
    }
    
    let actEditDone = () => {
        onEditDone(state.newText->Js_string2.trim)
    }
    
    let actEditCancel = () => {
        onEditCancel(state.newText->Js_string2.trim)
    }
    
    let actStartNewLine = () => {
        switch textFieldRef.current->Js.Nullable.toOption {
            | None => ()
            | Some(domElem) => {
                let input = ReactDOM.domElementToObj(domElem)
                let selectionStart = input["selectionStart"]
                let before = state.newText->Js.String2.substring(~from=0,~to_=selectionStart)
                let after = state.newText->Js.String2.substringToEnd(~from=selectionStart)
                actNewTextUpdated(before ++ "\n" ++ after)
                input["focus"](.)->ignore
                setNewTextCursorPosition(_ => Some(selectionStart+1))
            }
        }
    }

    let rndButtons = () => {
        let saveBtn = rndIconButton(
            ~icon=<MM_Icons.Save/>, ~active=true,  ~onClick=actEditDone, ~title="Save, Enter", ())
        let cancelBtn = rndIconButton(
            ~icon=<MM_Icons.CancelOutlined/>, ~onClick=actEditCancel, ~title="Cancel, Esc", ~color=None, ())
        let helpBtn = switch onHelp {
            | None => React.null
            | Some(onHelp) => {
                rndIconButton(
                    ~icon=<MM_Icons.HelpOutline/>, ~onClick=onHelp, ~title="Help", ~color=None, ()
                )
            }
        }
        let deleteBtn = switch onDelete {
            | None => React.null
            | Some(onDelete) => {
                rndIconButton(
                    ~icon=<MM_Icons.DeleteForever/>, ~onClick=onDelete, ~title="Clear", ~color=None, ()
                )
            }
        }
        let newLineBtn = rndIconButton(
            ~icon=<MM_Icons.KeyboardReturn/>, ~active=true,  ~onClick=actStartNewLine, 
            ~title="Start new line, Shift+Enter", ~color=None, ())
        <Row spacing=1.> saveBtn newLineBtn cancelBtn helpBtn deleteBtn </Row>
    }

    let rndText = () => {
        if (editMode) {
            let width = if (fullWidth) {
                let windowWidth = window["innerWidth"]
                windowWidth - 200
            } else {
                width
            }
            <Col>
                <TextField
                    inputRef=ReactDOM.Ref.domRef(textFieldRef)
                    size=#small
                    style=ReactDOM.Style.make(~width = width->Belt_Int.toString ++ "px", ())
                    autoFocus=true
                    multiline=true
                    value=state.newText
                    onChange=evt2str(actNewTextUpdated)
                    onKeyDown=kbrdHnd2(
                        kbrdClbkMake(~key=keyEnter, ~act=actEditDone, ()),
                        kbrdClbkMake(~key=keyEsc, ~act=actEditCancel, ()),
                    )
                    title="Enter to save, Shift+Enter to start a new line, Esc to cancel"
                />
                {rndButtons()}
            </Col>
        } else {
            let style = if (text->Js.String2.trim == "") {
                ReactDOM.Style.make(~padding="4px", ())
            } else {
                ReactDOM.Style.make(~padding="0px", ())
            }
            let title = if (editByAltClick) {
                if (longClickEnabled) {
                    "<long-click> (Alt + <left-click>) to change"
                } else {
                    "Alt + <left-click> to change"
                }
            } else {
                "<left-click> to change"
            }
            <Paper
                variant=#outlined 
                onClick
                onMouseDown onMouseUp onMouseMove onMouseLeave onMouseOut
                onTouchStart onTouchEnd onTouchMove onTouchCancel 
                style 
                title
            >
                {
                    if (text->Js.String2.trim == "" || renderer->Belt.Option.isNone) {
                        <pre>
                            {React.string(text)}
                        </pre>
                    } else {
                        (renderer->Belt.Option.getExn)(text)
                    }
                }
            </Paper>
        }
    }

    rndText()
}