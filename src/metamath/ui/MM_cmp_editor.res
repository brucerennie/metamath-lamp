open MM_context
open Expln_React_common
open Expln_React_Mui
open Expln_React_Modal
open MM_wrk_editor
open MM_wrk_editor_substitution
open MM_wrk_settings
open MM_wrk_unify
open Expln_utils_promise
open MM_react_common
open MM_statements_dto
open MM_wrk_editor_json
open MM_proof_tree
open MM_provers
open Local_storage_utils
open Common
open MM_wrk_pre_ctx_data
open MM_editor_history

let unifyAllIsRequiredCnt = ref(0)

let editorSaveStateToLocStor = (state:editorState, key:string, tempMode:bool):unit => {
    if (!tempMode) {
        locStorWriteString(key, Expln_utils_common.stringify(state->editorStateToEditorStateLocStor))
    }
}

let editorHistRegLocStorKey = "hist-reg"
let editorHistTmpLocStorKey = "hist-tmp"

let getHistLockStorKey = (tempMode:bool):string => {
    if (tempMode) { 
        editorHistTmpLocStorKey 
    } else { 
        editorHistRegLocStorKey 
    }
}

let histSaveToLocStor = (hist:editorHistory, tempMode:bool):unit => {
    let histStr = hist->editorHistToString
    locStorWriteString( getHistLockStorKey(tempMode), histStr )
}

let histReadFromLocStor = (~editorState:editorState, ~tempMode:bool, ~maxLength:int):editorHistory => {
    switch locStorReadString(getHistLockStorKey(tempMode)) {
        | None => editorHistMake(~initState=editorState, ~maxLength)
        | Some(histStr) => {
            switch editorHistFromString(histStr) {
                | Error(_) => editorHistMake(~initState=editorState, ~maxLength)
                | Ok(hist) => hist->editorHistAddSnapshot(editorState)
            }
        }
    }
}

let rndIconButton = (
    ~icon:reElem, 
    ~onClick:unit=>unit, 
    ~active:bool, 
    ~notifyEditInTempMode:option<(unit=>'a)=>'a>=?,
    ~ref:option<ReactDOM.domRef>=?,
    ~title:option<string>=?, 
    ~smallBtns:bool=false,
    ()
) => {
    <span ?ref ?title>
        <IconButton 
            disabled={!active} 
            onClick={_ => {
                switch notifyEditInTempMode {
                    | None => onClick()
                    | Some(notifyEditInTempMode) => notifyEditInTempMode(() => onClick())
                }
            }} 
            color="primary"
            style=?{
                if (smallBtns) {Some(ReactDOM.Style.make(~padding="2px", ()))} else {None}
            }
        > 
            icon 
        </IconButton>
    </span>
}

let editorStateLocStorKey = "editor-state"

let lastUsedAsrtSearchTypLocStorKey = "search-asrt-typ"

let saveLastUsedTyp = (ctx:mmContext,typInt:int,tempMode:bool):unit => {
    if (!tempMode) {
        switch ctx->ctxIntToSym(typInt) {
            | None => ()
            | Some(typStr) =>
                Dom_storage2.localStorage->Dom_storage2.setItem(lastUsedAsrtSearchTypLocStorKey, typStr)
        }
    }
}

let getLastUsedTyp = (ctx) => {
    switch Dom_storage2.localStorage->Dom_storage2.getItem(lastUsedAsrtSearchTypLocStorKey) {
        | None => None
        | Some(typStr) => ctx->ctxSymToInt(typStr)
    }
}

let jsonStrOptToEditorStateLocStor = (jsonStrOpt:option<string>):option<editorStateLocStor> => {
    jsonStrOpt->Belt_Option.flatMap(jsonStr => {
        readEditorStateFromJsonStr(jsonStr)->Belt.Result.mapWithDefault(None, state => Some(state))
    })
}

let previousEditingIsNotCompletedTitle = "Previous editing is not completed"
let previousEditingIsNotCompletedText = 
    `You've attempted to edit something in the editor while the previous edit is not complete.`
        ++ ` Please complete the previous edit before starting a new one.`

let editingInTempModeTitle = "Editing in TEMP mode"
let editingInTempModeText = 
    `You are about to edit in TEMP mode.`
        ++ ` All changes you do in TEMP mode will be erased upon closing current browser tab.`
        ++ ` If you want to continue editing in regular mode, please do the following actions:`
        ++ ` 1) use "Export to JSON" to copy current editor state to the clipboard;`
        ++ ` 2) open a new tab (or switch to an already opened tab) with metamath-lamp in regular mode;`
        ++ ` 3) use "Import from JSON" to load the copied editor state from the clipboard.`

@react.component
let make = (
    ~modalRef:modalRef, 
    ~preCtxData:preCtxData,
    ~top:int,
    ~reloadCtx: React.ref<Js.Nullable.t<MM_cmp_context_selector.reloadCtxFunc>>,
    ~loadEditorState: React.ref<Js.Nullable.t<editorStateLocStor => unit>>,
    ~initialStateJsonStr:option<string>,
    ~tempMode:bool,
    ~toggleCtxSelector:React.ref<Js.Nullable.t<unit=>unit>>,
    ~ctxSelectorIsExpanded:bool,
    ~showTabs:bool,
    ~setShowTabs:bool=>unit,
    ~openFrameExplorer:string=>unit,
) => {
    let (mainMenuIsOpened, setMainMenuIsOpened) = React.useState(_ => false)
    let mainMenuButtonRef = React.useRef(Js.Nullable.null)
    let (warnedAboutTempMode, setWarnedAboutTempMode) = React.useState(_ => false)

    let (showCheckbox, setShowCheckbox) = useStateFromLocalStorageBool(
        ~key="editor-showCheckbox", ~default=true,
    )
    let (showLabel, setShowLabel) = useStateFromLocalStorageBool(
        ~key="editor-showLabel", ~default=true,
    )
    let (showType, setShowType) = useStateFromLocalStorageBool(
        ~key="editor-showType", ~default=true,
    )
    let (showJstf, setShowJstf) = useStateFromLocalStorageBool(
        ~key="editor-showJstf", ~default=true,
    )
    let (inlineMode, setInlineMode) = useStateFromLocalStorageBool(
        ~key="editor-inlineMode", ~default=false,
    )
    let (smallBtns, setSmallBtns) = useStateFromLocalStorageBool(
        ~key="editor-smallBtns", ~default=false,
    )
    let (parenAc, setParenAc) = useStateFromLocalStorageBool(
        ~key="paren-autocomplete", ~default=true,
    )

    let (state, setStatePriv) = React.useState(_ => createInitialEditorState(
        ~preCtxData:preCtxData, 
        ~stateLocStor=jsonStrOptToEditorStateLocStor(initialStateJsonStr)
    ))
    let (hist, setHistPriv) = React.useState(() => {
        histReadFromLocStor(~editorState=state, ~tempMode, ~maxLength=preCtxData.settingsV.val.editorHistMaxLength)
    })

    let setHist = (update:editorHistory=>editorHistory):unit => {
        setHistPriv(ht => {
            let ht = update(ht)
            histSaveToLocStor(ht, tempMode)
            ht
        })
    }

    let setState = (update:editorState=>editorState) => {
        setStatePriv(st => {
            let st = updateEditorStateWithPostupdateActions(st, update)
            editorSaveStateToLocStor(st, editorStateLocStorKey, tempMode)
            setHist(ht => ht->editorHistAddSnapshot(st))
            st
        })
    }

    let notifyEditInTempMode = (continue:unit=>'a):'a => {
        if (tempMode && !warnedAboutTempMode) {
            openInfoDialog(
                ~modalRef, 
                ~title=editingInTempModeTitle,
                ~text=editingInTempModeText,
                ~onOk = () => {
                    setWarnedAboutTempMode(_ => true)
                    continue()
                },
                ()
            )
        } else {
            continue()
        }
    }

    let editIsActive = state->isEditMode

    let thereAreSyntaxErrors = editorStateHasErrors(state)
    let atLeastOneStmtIsChecked = state.checkedStmtIds->Js.Array2.length != 0
    let atLeastOneStmtHasSelectedText = state.stmts
        ->Js.Array2.find(stmt => stmt.cont->hasSelectedText)
        ->Belt.Option.isSome
    let mainCheckboxState = {
        let atLeastOneStmtIsNotChecked = state.stmts->Js.Array2.length != state.checkedStmtIds->Js.Array2.length
        if ((atLeastOneStmtIsChecked || atLeastOneStmtHasSelectedText) && atLeastOneStmtIsNotChecked) {
            None
        } else if (atLeastOneStmtIsChecked && !atLeastOneStmtIsNotChecked) {
            Some(true)
        } else {
            Some(false)
        }
    }

    let generalModificationActionIsEnabled = !editIsActive && !thereAreSyntaxErrors
    let singleProvableChecked = switch getTheOnlyCheckedStmt(state) {
        | Some(stmt) if stmt.typ == P => Some(stmt)
        | _ => None
    }
    let numOfCheckedStmts = state.checkedStmtIds->Js.Array2.length
    let thereIsDuplicatedStmt = state->editorStateHasDuplicatedStmts

    let actPreCtxDataUpdated = () => {
        setState(setPreCtxData(_, preCtxData))
        setHist(editorHistSetMaxLength(_, preCtxData.settingsV.val.editorHistMaxLength))
    }

    React.useEffect1(() => {
        actPreCtxDataUpdated()
        None
    }, [preCtxData.settingsV.ver, preCtxData.ctxV.ver])

    let actOpenMainMenu = () => {
        setMainMenuIsOpened(_ => true)
    }

    let actCloseMainMenu = () => {
        setMainMenuIsOpened(_ => false)
    }

    let actAddNewStmt = () => {
        setState(st => {
            let (st, _) = addNewStmt(st)
            st
        })
    }
    let actDeleteCheckedStmts = () => {
        openModal(modalRef, _ => React.null)->promiseMap(modalId => {
            updateModal(modalRef, modalId, () => {
                <Paper style=ReactDOM.Style.make(~padding="10px", ())>
                    <Col spacing=1.>
                        {
                            let numOfSelectedStmts = state.checkedStmtIds->Js.Array2.length
                            if (numOfSelectedStmts == state.stmts->Js.Array2.length) {
                                React.string("Delete all steps?")
                            } else if (numOfSelectedStmts == 1) {
                                React.string("Delete the selected step?")
                            } else {
                                React.string(`Delete ${state.checkedStmtIds->Js.Array2.length->Belt.Int.toString}` 
                                                ++ ` selected steps?`)
                            }
                        }
                        <Row>
                            <Button onClick={_=>closeModal(modalRef, modalId)}> {React.string("Cancel")} </Button>
                            <Button
                                onClick={_=>{
                                    closeModal(modalRef, modalId)
                                    setState(deleteCheckedStmts)
                                }}
                                variant=#contained
                            > 
                                {React.string("Delete")} 
                            </Button>
                        </Row>
                    </Col>
                </Paper>
            })
        })->ignore
    }
    let actToggleStmtChecked = id => {
        setStatePriv(st => {
            let st = toggleStmtChecked(st,id)
            editorSaveStateToLocStor(st, editorStateLocStorKey, tempMode)
            st
        })
    }
    let actToggleMainCheckbox = () => {
        let action = switch mainCheckboxState {
            | Some(true) | None => uncheckAllStmts
            | Some(false) => checkAllStmts
        }
        setStatePriv(st => {
            let st = action(st)
            editorSaveStateToLocStor(st, editorStateLocStorKey, tempMode)
            st
        })
    }
    let actMoveCheckedStmtsUp = () => setState(moveCheckedStmts(_, true))
    let actMoveCheckedStmtsDown = () => setState(moveCheckedStmts(_, false))
    let actDuplicateStmt = (top:bool) => setState(st => {
        let st = duplicateCheckedStmt(st,top)
        let st = uncheckAllStmts(st)
        st
    })
    let actAddStmtAbove = (id:stmtId, text:string):unit => {
        setState(st => {
            let st = uncheckAllStmts(st)
            let st = toggleStmtChecked(st,id)
            let (st, newId) = addNewStmt(st)
            let st = setStmtCont(st, newId, text->strToCont(()))
            let st = uncheckAllStmts(st)
            st
        })
    }
    let actAddStmtBelow = (id:stmtId, text:string):unit => {
        setState(st => {
            let st = uncheckAllStmts(st)
            let st = switch st.stmts->Js.Array2.findIndex(stmt => stmt.id == id) {
                | -1 => st
                | idx => {
                    if (idx == st.stmts->Js.Array2.length-1) {
                        st
                    } else {
                        toggleStmtChecked(st,st.stmts[idx+1].id)
                    }
                }
            }
            let (st, newId) = addNewStmt(st)
            let st = setStmtCont(st, newId, text->strToCont(()))
            let st = uncheckAllStmts(st)
            st
        })
    }

    let actBeginEdit0 = (setter:editorState=>editorState) => {
        notifyEditInTempMode(() => {
            if (!editIsActive) {
                setState(setter)
            } else {
                openInfoDialog(
                    ~modalRef, 
                    ~title=previousEditingIsNotCompletedTitle,
                    ~text=previousEditingIsNotCompletedText,
                    ()
                )
            }
        })
    }
    let actBeginEdit = (setter:(editorState,stmtId)=>editorState, stmtId:string) => {
        notifyEditInTempMode(() => {
            if (!editIsActive) {
                setState(setter(_,stmtId))
            } else {
                openInfoDialog(
                    ~modalRef, 
                    ~title=previousEditingIsNotCompletedTitle,
                    ~text=previousEditingIsNotCompletedText,
                    ()
                )
            }
        })
    }
    let actCompleteEdit = (setter:editorState=>editorState) => {
        setState(setter)
    }

    let actDescrEditComplete = newText => {
        setState(completeDescrEditMode(_,newText))
    }

    let actVarsEditComplete = newText => {
        setState(completeVarsEditMode(_,newText))
    }

    let actDisjEditComplete = newText => {
        setState(completeDisjEditMode(_,newText))
    }

    let actSyntaxTreeUpdated = (setter:editorState=>editorState) => {
        setState(setter)
    }

    let actCompleteEditLabel = (stmtId, newLabel):unit => {
        let newLabel = newLabel->Js_string2.trim
        switch state->renameStmt(stmtId, newLabel) {
            | Error(msg) => openInfoDialog( ~modalRef, ~text=`Cannot rename this step: ${msg}`, () )
            | Ok(st) => setState(_ => completeLabelEditMode(st,stmtId,newLabel))
        }
    }

    let actCancelEditLabel = (stmtId, newLabel):unit => {
        switch state->editorGetStmtById(stmtId) {
            | None => ()
            | Some(stmt) => {
                let textOld = stmt.label
                let textNew = newLabel
                if (textOld == textNew || textNew == "") {
                    setState(completeLabelEditMode(_,stmtId,textOld))
                } else {
                    openModal(modalRef, _ => React.null)->promiseMap(modalId => {
                        updateModal(modalRef, modalId, () => {
                            <MM_cmp_save_or_discard
                                contOld={React.string(textOld)}
                                contNew={React.string(textNew)}
                                onDiscard={() => {
                                    closeModal(modalRef, modalId)
                                    setState(completeLabelEditMode(_,stmtId,textOld))
                                }}
                                onSave={() => {
                                    closeModal(modalRef, modalId)
                                    actCompleteEditLabel(stmtId, textNew)
                                }}
                                onContinueEditing={() => {
                                    closeModal(modalRef, modalId)
                                }}
                            />
                        })
                    })->ignore
                }
            }
        }
    }

    let actCancelEditCont = (stmtId, newContText):unit => {
        switch state->editorGetStmtById(stmtId) {
            | None => ()
            | Some(stmt) => {
                let contOld = stmt.cont
                let contNew = newContText->strToCont(())
                let textOld = contOld->contToStr
                let textNew = contNew->contToStr
                if (textOld == textNew || (textOld == "" && textNew == state.settings.defaultStmtType->Js.String2.trim)) {
                    if (textOld == "") {
                        setState(deleteStmt(_,stmtId))
                    } else {
                        setState(completeContEditMode(_,stmtId,textOld))
                    }
                } else {
                    if (textNew == "") {
                        setState(completeContEditMode(_,stmtId,textOld))
                    } else {
                        openModal(modalRef, _ => React.null)->promiseMap(modalId => {
                            updateModal(modalRef, modalId, () => {
                                <MM_cmp_save_or_discard
                                    removeStmt={textOld == ""}
                                    contOld={MM_cmp_user_stmt.rndContText(~stmtCont=contOld, ())}
                                    contNew={MM_cmp_user_stmt.rndContText(~stmtCont=contNew, ())}
                                    onDiscard={() => {
                                        closeModal(modalRef, modalId)
                                        if (textOld == "") {
                                            setState(deleteStmt(_,stmtId))
                                        } else {
                                            setState(completeContEditMode(_,stmtId,textOld))
                                        }
                                    }}
                                    onSave={() => {
                                        closeModal(modalRef, modalId)
                                        setState(completeContEditMode(_,stmtId,textNew))
                                    }}
                                    onContinueEditing={() => {
                                        closeModal(modalRef, modalId)
                                    }}
                                />
                            })
                        })->ignore
                    }
                }
            }
        }
    }

    let actCancelEditJstf = (stmtId, newJstfText):unit => {
        switch state->editorGetStmtById(stmtId) {
            | None => ()
            | Some(stmt) => {
                let textOld = switch stmt.typ {
                    | E => defaultJstfForHyp
                    | P => stmt.jstfText->Js_string2.trim
                }
                let newJstfTextTrim = newJstfText->Js_string2.trim
                let textNew = switch stmt.typ {
                    | P => newJstfTextTrim
                    | E => {
                        if (defaultJstfForHyp == newJstfTextTrim->Js.String2.toUpperCase) {
                            defaultJstfForHyp
                        } else {
                            newJstfTextTrim
                        }
                    }
                }
                let nothingChanged = textOld == textNew
                if (nothingChanged) {
                    setState(completeJstfEditMode(_,stmtId,textOld))
                } else {
                    openModal(modalRef, _ => React.null)->promiseMap(modalId => {
                        updateModal(modalRef, modalId, () => {
                            <MM_cmp_save_or_discard
                                contOld={React.string(textOld)}
                                contNew={React.string(textNew)}
                                onDiscard={() => {
                                    closeModal(modalRef, modalId)
                                    setState(completeJstfEditMode(_,stmtId,textOld))
                                }}
                                onSave={() => {
                                    closeModal(modalRef, modalId)
                                    setState(completeJstfEditMode(_,stmtId,textNew))
                                }}
                                onContinueEditing={() => {
                                    closeModal(modalRef, modalId)
                                }}
                            />
                        })
                    })->ignore
                }
            }
        }
    }

    let actCancelEditDescr = (newText):unit => {
        let textOld = state.descr->Js_string2.trim
        let textNew = newText->Js_string2.trim
        if (textOld == textNew || textNew == "") {
            setState(completeDescrEditMode(_,textOld))
        } else {
            openModal(modalRef, _ => React.null)->promiseMap(modalId => {
                updateModal(modalRef, modalId, () => {
                    <MM_cmp_save_or_discard
                        contOld={<pre>{React.string(textOld)}</pre>}
                        contNew={<pre>{React.string(textNew)}</pre>}
                        onDiscard={() => {
                            closeModal(modalRef, modalId)
                            setState(completeDescrEditMode(_,textOld))
                        }}
                        onSave={() => {
                            closeModal(modalRef, modalId)
                            setState(completeDescrEditMode(_,textNew))
                        }}
                        onContinueEditing={() => {
                            closeModal(modalRef, modalId)
                        }}
                    />
                })
            })->ignore
        }
    }

    let actCancelEditVars = (newText):unit => {
        let textOld = state.varsText->Js_string2.trim
        let textNew = newText->Js_string2.trim
        if (textOld == textNew || textNew == "") {
            setState(completeVarsEditMode(_,textOld))
        } else {
            openModal(modalRef, _ => React.null)->promiseMap(modalId => {
                updateModal(modalRef, modalId, () => {
                    <MM_cmp_save_or_discard
                        contOld={<pre>{React.string(textOld)}</pre>}
                        contNew={<pre>{React.string(textNew)}</pre>}
                        onDiscard={() => {
                            closeModal(modalRef, modalId)
                            setState(completeVarsEditMode(_,textOld))
                        }}
                        onSave={() => {
                            closeModal(modalRef, modalId)
                            setState(completeVarsEditMode(_,textNew))
                        }}
                        onContinueEditing={() => {
                            closeModal(modalRef, modalId)
                        }}
                    />
                })
            })->ignore
        }
    }

    let actCancelEditDisj = (newText):unit => {
        let textOld = state.disjText->Js_string2.trim
        let textNew = newText->Js_string2.trim
        if (textOld == textNew || textNew == "") {
            setState(completeDisjEditMode(_,textOld))
        } else {
            openModal(modalRef, _ => React.null)->promiseMap(modalId => {
                updateModal(modalRef, modalId, () => {
                    <MM_cmp_save_or_discard
                        contOld={<pre>{React.string(textOld)}</pre>}
                        contNew={<pre>{React.string(textNew)}</pre>}
                        onDiscard={() => {
                            closeModal(modalRef, modalId)
                            setState(completeDisjEditMode(_,textOld))
                        }}
                        onSave={() => {
                            closeModal(modalRef, modalId)
                            setState(completeDisjEditMode(_,textNew))
                        }}
                        onContinueEditing={() => {
                            closeModal(modalRef, modalId)
                        }}
                    />
                })
            })->ignore
        }
    }

    let actToggleParenAc = () => {
        setParenAc(prev => !prev)
    }

    let actAsrtSearchResultsSelected = selectedResults => {
        setState(st => selectedResults->Js_array2.reduce( addNewStatements, st ))
    }

    let actBottomUpResultSelected = (selectedResult:stmtsDto) => {
        setState(st => {
            let st = st->addNewStatements(selectedResult)
            let st = st->uncheckAllStmts
            let st = st->incUnifyAllIsRequiredCnt
            st
        })
    }

    let actWrkSubsSelected = wrkSubs => {
        setState(st => st->applySubstitutionForEditor(wrkSubs))
    }

    let actOnMergeStmtsSelected = (~stmtToUse:userStmt,~stmtToRemove:userStmt,~continueMergingStmts:bool) => {
        setState(st => {
            switch st->mergeStmts(stmtToUse.id, stmtToRemove.id) {
                | Ok(st) => {
                    let st = st->uncheckAllStmts
                    if (continueMergingStmts) {
                        let st = st->updateEditorStateWithPostupdateActions(st => st)
                        if (st->editorStateHasDuplicatedStmts) {
                            st->incContinueMergingStmts
                        } else {
                            st
                        }
                    } else {
                        st
                    }
                }
                | Error(msg) => {
                    openInfoDialog(~modalRef, ~text=msg, ())
                    st
                }
            }
        })
    }

    let actRestorePrevState = (histIdx:int):unit => {
        notifyEditInTempMode(() => {
            switch state->restoreEditorStateFromSnapshot(hist, histIdx) {
                | Error(msg) => openInfoDialog( ~modalRef, ~title="Could not restore editor state", ~text=msg, () )
                | Ok(editorState) => setState(_ => editorState->recalcWrkColors)
            }
        })
    }

    let viewOptions = { 
        MM_cmp_user_stmt.showCheckbox:showCheckbox, 
        showLabel, showType, showJstf, inlineMode, 
        smallBtns, 
    }

    let actOpenRestorePrevStateDialog = () => {
        openModalFullScreen(modalRef, () => React.null)->promiseMap(modalId => {
            updateModal(modalRef, modalId, () => {
                <MM_cmp_editor_hist 
                    modalRef
                    editorState={state->removeAllTempData}
                    hist 
                    onClose={_=>closeModal(modalRef, modalId)} 
                    viewOptions
                    onRestore={histIdx => {
                        actRestorePrevState(histIdx)
                        closeModal(modalRef, modalId)
                    }}
                />
            })
        })->ignore
    }

    let actMergeStmts = () => {
        switch state->findStmtsToMerge {
            | Error(msg) => {
                openInfoDialog(
                    ~modalRef, 
                    ~text=msg,
                    ()
                )
            }
            | Ok((stmt1,stmt2)) => {
                openModal(modalRef, _ => React.null)->promiseMap(modalId => {
                    updateModal(modalRef, modalId, () => {
                        <MM_cmp_merge_two_stmts
                            stmt1
                            stmt2
                            onStmtSelected={(stmtToUse,stmtToRemove)=>{
                                closeModal(modalRef, modalId)
                                actOnMergeStmtsSelected(
                                    ~stmtToUse, ~stmtToRemove, ~continueMergingStmts = numOfCheckedStmts==0
                                )
                            }}
                            onCancel={()=>closeModal(modalRef, modalId)}
                        />
                    })
                })->ignore
            }
        }
    }

    React.useEffect1(() => {
        if (state->editorStateHasDuplicatedStmts) {
            actMergeStmts()
        }
        None
    }, [state.continueMergingStmts])

    let actSearchAsrt = () => {
        switch state.wrkCtx {
            | None => ()
            | Some(wrkCtx) => {
                openModal(modalRef, _ => React.null)->promiseMap(modalId => {
                    updateModal(modalRef, modalId, () => {
                        <MM_cmp_search_asrt
                            modalRef
                            settingsVer=state.settingsV
                            settings=state.settings
                            preCtxVer=state.preCtxV
                            preCtx=state.preCtx
                            varsText=state.varsText
                            disjText=state.disjText
                            wrkCtx
                            frms=state.frms
                            initialTyp={getLastUsedTyp(state.preCtx)}
                            onTypChange={saveLastUsedTyp(state.preCtx, _, tempMode)}
                            onCanceled={()=>closeModal(modalRef, modalId)}
                            onResultsSelected={selectedResults=>{
                                closeModal(modalRef, modalId)
                                actAsrtSearchResultsSelected(selectedResults)
                            }}
                        />
                    })
                })->ignore
            }
        }
    }

    let getSelectionText = (stmt:userStmt):option<(string,Js_date.t)> => {
        switch stmt.cont {
            | Text(_) => None
            | Tree({clickedNodeId}) => {
                switch clickedNodeId {
                    | None => None
                    | Some((_,time)) => stmt.cont->getSelectedText->Belt.Option.map(str => (str,time))
                }
            }
        }
    }

    let getStmtTextIfChecked = (st:editorState,stmt:userStmt):option<(string,Js_date.t)> => {
        st.checkedStmtIds->Js.Array2.find(((id,_)) => id == stmt.id)
            ->Belt_Option.map(((_,time)) => (stmt.cont->contToStr, time))
    }

    let getSelectedExpr = (st:editorState,stmt:userStmt):option<(string,Js_date.t)> => {
        switch getSelectionText(stmt) {
            | Some(res) => Some(res)
            | None => getStmtTextIfChecked(st,stmt)
        }
    }

    let getExprsToSubstitute = (st:editorState):(option<string>,option<string>) => {
        let selections = st.stmts->Js.Array2.map(stmt => getSelectedExpr(st,stmt))
            ->Js.Array2.filter(Belt_Option.isSome)
            ->Js.Array2.map(Belt_Option.getExn)
            ->Js.Array2.sortInPlaceWith(((_,time1),(_,time2)) => compareDates(time1,time2) )
        let len = selections->Js.Array2.length
        let sel1 = selections->Belt_Array.get(len-2)->Belt.Option.map(((str,_)) => str)
        let sel2 = selections->Belt_Array.get(len-1)->Belt.Option.map(((str,_)) => str)
        switch len {
            | 0 => (None, None)
            | 1 => (sel2, None)
            | _ => (sel1, sel2)
        }
    }

    let actSubstitute = () => {
        switch state.wrkCtx {
            | None => ()
            | Some(wrkCtx) => {
                let (expr1Init,expr2Init) = getExprsToSubstitute(state)
                openModal(modalRef, _ => React.null)->promiseMap(modalId => {
                    updateModal(modalRef, modalId, () => {
                        <MM_cmp_substitution
                            modalRef
                            editorState=state
                            expr1Init
                            expr2Init
                            wrkCtx
                            onCanceled={()=>closeModal(modalRef, modalId)}
                            onSubstitutionSelected={wrkSubs=>{
                                closeModal(modalRef, modalId)
                                actWrkSubsSelected(wrkSubs)
                            }}
                        />
                    })
                })->ignore
            }
        }
    }

    let actUnifyAllResultsAreReady = proofTreeDto => {
        setStatePriv(st => {
            let st = applyUnifyAllResults(st, proofTreeDto)
            editorSaveStateToLocStor(st, editorStateLocStorKey, tempMode)
            setHist(ht => ht->editorHistAddSnapshot(st))
            st
        })
    }

    let makeActTerminate = (modalId:modalId):(unit=>unit) => {
        () => {
            MM_wrk_client.terminateWorker()
            closeModal(modalRef, modalId)
        }
    }

    let prepareArgs0 = (argLabels:array<string>, rootStmts:array<rootStmt>):array<expr> => {
        rootStmts
            ->Js_array2.filter(stmt => argLabels->Js_array2.includes(stmt.label))
            ->Js_array2.map(stmt => stmt.expr)
    }

    let getArgs0AndAsrtLabel = (jstfText:string, rootStmts:array<rootStmt>):option<(array<expr>,string)> => {
        switch jstfText->parseJstf {
            | Error(_) | Ok(None) => None
            | Ok(Some({args:argLabels, label})) => Some((prepareArgs0(argLabels, rootStmts), label))
        }
    }

    let actUnify = (
        ~stmtId:option<stmtId>=?,
        ~params:option<bottomUpProverParams>=?,
        ~initialDebugLevel:option<int>=?,
        ()
    ) => {
        switch state.wrkCtx {
            | None => ()
            | Some(wrkCtx) => {
                let varsText=state.varsText
                let disjText=state.disjText
                let state = switch stmtId {
                    | None => state
                    | Some(stmtId) => {
                        let state = state->uncheckAllStmts
                        let state = state->toggleStmtChecked(stmtId)
                        state
                    }
                }
                let rootUserStmts = state->getRootStmtsForUnification
                let rootStmts = rootUserStmts->Js.Array2.map(userStmtToRootStmt)
                let singleProvableChecked = switch getTheOnlyCheckedStmt(state) {
                    | Some(stmt) if stmt.typ == P => Some(stmt)
                    | _ => None
                }
                switch singleProvableChecked {
                    | Some(singleProvableChecked) => {
                        let initialParams = switch params {
                            | Some(_) => params
                            | None => {
                                switch getArgs0AndAsrtLabel(singleProvableChecked.jstfText, rootStmts) {
                                    | None => None
                                    | Some((args0,asrtLabel)) => Some(bottomUpProverParamsMake(~asrtLabel, ~args0, ()))
                                }
                            }
                        }
                        openModal(modalRef, _ => React.null)->promiseMap(modalId => {
                            updateModal(modalRef, modalId, () => {
                                <MM_cmp_unify_bottom_up
                                    modalRef
                                    settingsVer=state.settingsV
                                    settings=state.settings
                                    preCtxVer=state.preCtxV
                                    preCtx=state.preCtx
                                    frms=state.frms parenCnt=state.parenCnt
                                    varsText disjText wrkCtx
                                    rootStmts=rootUserStmts
                                    reservedLabels={state.stmts->Js_array2.map(stmt => stmt.label)}
                                    typeToPrefix = {
                                        Belt_MapString.fromArray(
                                            state.settings.typeSettings->Js_array2.map(ts => (ts.typ, ts.prefix))
                                        )
                                    }
                                    initialParams=?initialParams
                                    initialDebugLevel=?initialDebugLevel
                                    onResultSelected={newStmtsDto => {
                                        closeModal(modalRef, modalId)
                                        actBottomUpResultSelected(newStmtsDto)
                                    }}
                                    onCancel={() => closeModal(modalRef, modalId)}
                                />
                            })
                        })->ignore
                    }
                    | None => {
                        openModal(modalRef, () => rndProgress(~text="Unifying all", ~pct=0., ()))->promiseMap(modalId => {
                            updateModal( 
                                modalRef, modalId, () => rndProgress(
                                    ~text="Unifying all", ~pct=0., ~onTerminate=makeActTerminate(modalId), ()
                                )
                            )
                            let rootStmts = rootUserStmts->Js_array2.map(userStmtToRootStmt)
                            unify(
                                ~settingsVer=state.settingsV,
                                ~settings=state.settings,
                                ~preCtxVer=state.preCtxV,
                                ~preCtx=state.preCtx,
                                ~varsText,
                                ~disjText,
                                ~rootStmts,
                                ~bottomUpProverParams=None,
                                ~allowedFrms=state.settings.allowedFrms,
                                ~syntaxTypes=Some(state.syntaxTypes),
                                ~exprsToSyntaxCheck=
                                    if (state.settings.checkSyntax) {
                                        Some(state->getAllExprsToSyntaxCheck(rootStmts))
                                    } else {
                                        None
                                    },
                                ~debugLevel=0,
                                ~onProgress = msg => updateModal(
                                    modalRef, modalId, () => rndProgress(
                                        ~text=msg, ~onTerminate=makeActTerminate(modalId), ()
                                    )
                                )
                            )->promiseMap(proofTreeDto => {
                                closeModal(modalRef, modalId)
                                actUnifyAllResultsAreReady(proofTreeDto)
                            })
                        })->ignore
                    }
                }
            }
        }
    }

    React.useEffect1(() => {
        if (unifyAllIsRequiredCnt.contents < state.unifyAllIsRequiredCnt) {
            unifyAllIsRequiredCnt.contents = state.unifyAllIsRequiredCnt
            if (!editorStateHasErrors(state)) {
                actUnify(())
            }
        }
        None
    }, [state.unifyAllIsRequiredCnt])

    let actExportProof = (stmtId) => {
        switch generateCompressedProof(state, stmtId) {
            | None => ()
            | Some((proofText,proofTableWithTypes,proofTableWithoutTypes)) => {
                openModal(modalRef, () => React.null)->promiseMap(modalId => {
                    updateModal(modalRef, modalId, () => {
                        <MM_cmp_export_proof 
                            proofText proofTableWithTypes proofTableWithoutTypes 
                            onClose={_=>closeModal(modalRef, modalId)} 
                        />
                    })
                })->ignore
            }
        }
    }

    let currGoalStmtStatus:option<(stmtId,string,option<proofStatus>)> = state.stmts
        ->Js.Array2.find(stmt => stmt.isGoal)
        ->Belt.Option.map(stmt => (stmt.id, stmt.cont->contToStr, stmt.proofStatus))
    let prevGoalStmtStatus:React.ref<(string,proofStatus)> = React.useRef(("",NoJstf))
    React.useEffect1(() => {
        switch currGoalStmtStatus {
            | None => ()
            | Some((curGoalId,curGoalText,currGoalStatus)) => {
                switch currGoalStatus {
                    | None => prevGoalStmtStatus.current = (curGoalText,NoJstf)
                    | Some(currGoalStatus) => {
                        let (prevGoalText,prevGoalStatus) = prevGoalStmtStatus.current
                        if (currGoalStatus == Ready && (prevGoalStatus != Ready || curGoalText != prevGoalText)) {
                            actExportProof(curGoalId)
                        }
                        prevGoalStmtStatus.current = (curGoalText,currGoalStatus)
                    }
                }
            }
        }
        None
    }, [currGoalStmtStatus])

    let actExportToJson = () => {
        openModal(modalRef, () => React.null)->promiseMap(modalId => {
            updateModal(modalRef, modalId, () => {
                <MM_cmp_export_state_to_json 
                    jsonStr=Expln_utils_common.stringify(state->editorStateToEditorStateLocStor)
                    onClose={_=>closeModal(modalRef, modalId)}
                />
            })
        })->ignore
    }

    let actExportToUrl = () => {
        openModal(modalRef, () => React.null)->promiseMap(modalId => {
            updateModal(modalRef, modalId, () => {
                <MM_cmp_export_state_to_url 
                    editorStateBase64=strToSafeBase64(Expln_utils_common.stringify(state->editorStateToEditorStateLocStor))
                    onClose={_=>closeModal(modalRef, modalId)} 
                />
            })
        })->ignore
    }

    let rndSrcDtos = (srcs:array<mmCtxSrcDto>):reElem => {
        <Col>
        {
            srcs->Js_array2.mapi((src,i) => {
                <Paper key={i->Belt.Int.toString} style=ReactDOM.Style.make(~padding="3px", ())>
                    <Col>
                        {src.url->React.string}
                        {
                            let readInstr = src.readInstr->readInstrFromStr
                            if (readInstr == ReadAll) {
                                `read all`->React.string
                            } else {
                                let readInstrStr = if (readInstr == StopBefore) {"stop before"} else {"stop after"}
                                `${readInstrStr}: ${src.label}`->React.string
                            }
                        }
                    </Col>
                </Paper>
            })->React.array
        }
        </Col>
    }

    let loadEditorStatePriv = (stateLocStor:editorStateLocStor):unit => {
        setState(_ => createInitialEditorState( ~preCtxData, ~stateLocStor=Some(stateLocStor) ))
        reloadCtx.current->Js.Nullable.toOption->Belt.Option.forEach(reloadCtx => {
            reloadCtx(~srcs=stateLocStor.srcs, ~settings=state.settings, ())->promiseMap(res => {
                switch res {
                    | Ok(_) => ()
                    | Error(msg) => {
                        openModal(modalRef, _ => React.null)->promiseMap(modalId => {
                            updateModal(modalRef, modalId, () => {
                                <Paper style=ReactDOM.Style.make(~padding="10px", ())>
                                    <Col spacing=1.>
                                        <span style=ReactDOM.Style.make(~fontWeight="bold", ())>
                                            { React.string(`Could not reload the context because of the error:`) }
                                        </span>
                                        <span style=ReactDOM.Style.make(~color="red", ())>
                                            { React.string(msg) }
                                        </span>
                                        <span>
                                            { React.string(`This error happened when loading the context:`) }
                                        </span>
                                        {rndSrcDtos(stateLocStor.srcs)}
                                        <Button onClick={_ => closeModal(modalRef, modalId) } variant=#contained> 
                                            {React.string("Ok")} 
                                        </Button>
                                    </Col>
                                </Paper>
                            })
                        })->ignore
                    }
                }
            })->ignore
        })
    }
    loadEditorState.current = Js.Nullable.return(loadEditorStatePriv)

    let actImportFromJson = (jsonStr:string):bool => {
        switch readEditorStateFromJsonStr(jsonStr) {
            | Error(errorMsg) => {
                openModal(modalRef, _ => React.null)->promiseMap(modalId => {
                    updateModal(modalRef, modalId, () => {
                        <Paper style=ReactDOM.Style.make(~padding="10px", ())>
                            <Col spacing=1.>
                                { React.string(errorMsg) }
                                <Button onClick={_ => closeModal(modalRef, modalId) } variant=#contained> 
                                    {React.string("Ok")} 
                                </Button>
                            </Col>
                        </Paper>
                    })
                })->ignore
                false
            }
            | Ok(stateLocStor) => {
                loadEditorStatePriv(stateLocStor)
                true
            }
        }
    }

    React.useEffect0(() => {
        switch initialStateJsonStr {
            | None => ()
            | Some(jsonStr) => actImportFromJson(jsonStr)->ignore
        }
        None
    })

    let actOpenImportFromJsonDialog = () => {
        openModal(modalRef, () => React.null)->promiseMap(modalId => {
            updateModal(modalRef, modalId, () => {
                <MM_cmp_import_from_json
                    onImport={text=>{
                        if (actImportFromJson(text)) {
                            closeModal(modalRef, modalId)
                        }
                    }}
                    onCancel={()=>closeModal(modalRef, modalId)}
                />
            })
        })->ignore
    }

    let actShowInfoAboutGettingCompletedProof = (title:string) => {
        openInfoDialog( 
            ~modalRef, 
            ~title,
            ~text=`In order to show a completed proof please do the following: ` 
                ++ `1) Make sure the step you want to show a completed proof for is marked with a green chekmark. ` 
                ++ `If it is not, try to "unify all"; 2) Select the step you want to show a completed proof for; ` 
                ++ `3) Select "Show completed proof" menu item.`, 
            () 
        )
    }

    let actShowCompletedProof = () => {
        switch state->getTheOnlyCheckedStmt {
            | Some(stmt) if stmt.typ == P => {
                switch stmt.proofStatus {
                    | Some(Ready) => actExportProof(stmt.id)
                    | Some(Waiting) | Some(NoJstf) | Some(JstfIsIncorrect) | None => 
                        actShowInfoAboutGettingCompletedProof(`A proof is not available`)
                }
            }
            | _ => actShowInfoAboutGettingCompletedProof(`A single provable step should be selected`)
        }
    }

    let actRenumberSteps = () => {
        notifyEditInTempMode(() => {
            switch state->renumberSteps {
                | Ok(state) => setState(_ => state)
                | Error(msg) => openInfoDialog( ~modalRef, ~text=msg, () )
            }
        })
    }

    let actDebugUnifyAll = (stmtId) => {
        let st = state
        let st = st->uncheckAllStmts
        let st = st->toggleStmtChecked(stmtId)
        let singleProvableChecked = switch getTheOnlyCheckedStmt(st) {
            | Some(stmt) if stmt.typ == P => Some(stmt)
            | _ => None
        }
        switch singleProvableChecked {
            | None => ()
            | Some(singleProvableChecked) => {
                let rootUserStmts = st->getRootStmtsForUnification
                let rootStmts = rootUserStmts->Js.Array2.map(userStmtToRootStmt)
                let params = switch getArgs0AndAsrtLabel(singleProvableChecked.jstfText, rootStmts) {
                    | Some((args0,asrtLabel)) => {
                        bottomUpProverParamsMake(
                            ~args0, 
                            ~args1=[],
                            ~asrtLabel, 
                            ~maxSearchDepth=1,
                            ~lengthRestrict=Less,
                            ~allowNewDisjForExistingVars=false,
                            ~allowNewStmts=false,
                            ~allowNewVars=false,
                            ~maxNumberOfBranches=?None,
                            ()
                        )
                    }
                    | None => {
                        bottomUpProverParamsMake(
                            ~args0=rootStmts->Js_array2.map(stmt => stmt.expr), 
                            ~args1=[],
                            ~asrtLabel=?None, 
                            ~maxSearchDepth=1,
                            ~lengthRestrict=Less,
                            ~allowNewDisjForExistingVars=false,
                            ~allowNewStmts=false,
                            ~allowNewVars=false,
                            ~maxNumberOfBranches=?None,
                            ()
                        )
                    }
                }
                actUnify(
                    ~stmtId, 
                    ~params, 
                    ~initialDebugLevel = if (params.asrtLabel->Belt_Option.isSome) {2} else {1}, 
                    ()
                )
            }
        }
    }

    let actOpenViewOptionsDialog = () => {
        openModal(modalRef, _ => React.null)->promiseMap(modalId => {
            updateModal(modalRef, modalId, () => {
                <MM_cmp_editor_view_options
                    onClose={()=>closeModal(modalRef, modalId)}
                    showCheckbox onShowCheckboxChange = {b => setShowCheckbox(_ => b) }
                    showLabel onShowLabelChange = {b => setShowLabel(_ => b) }
                    showType onShowTypeChange = {b => setShowType(_ => b) }
                    showJstf onShowJstfChange = {b => setShowJstf(_ => b) }
                    inlineMode onInlineModeChange = {b => setInlineMode(_ => b) }
                    smallBtns onSmallBtnsChange = {b => setSmallBtns(_ => b) }
                />
            })
        })->ignore
    }

    let actResetEditorContent = () => {
        setState(resetEditorContent)
    }

    let rndError = (msgOpt,color) => {
        switch msgOpt {
            | None => <></>
            | Some(msg) => <pre style=ReactDOM.Style.make(~color, ())>{React.string(msg)}</pre>
        }
    }

    let rndMainMenu = () => {
        if (mainMenuIsOpened) {
            switch mainMenuButtonRef.current->Js.Nullable.toOption {
                | None => React.null
                | Some(mainMenuButtonRef) => {
                    <Menu
                        opn=true
                        anchorEl=mainMenuButtonRef
                        onClose=actCloseMainMenu
                    >
                        <MenuItem
                            onClick={() => {
                                actCloseMainMenu()
                                setShowTabs(!showTabs)
                            }}
                        >
                            {React.string(if (showTabs) {"Hide tabs"} else {"Show tabs"})}
                        </MenuItem>
                        <MenuItem
                            onClick={() => {
                                actCloseMainMenu()
                                toggleCtxSelector.current->Js.Nullable.toOption
                                    ->Belt.Option.forEach(toggleCtxSelector => toggleCtxSelector())
                            }}
                        >
                            {React.string(if ctxSelectorIsExpanded {"Hide context"} else {"Show context"})}
                        </MenuItem>
                        <MenuItem
                            onClick={() => {
                                actCloseMainMenu()
                                actOpenViewOptionsDialog()
                            }}
                        >
                            {React.string("View options")}
                        </MenuItem>
                        <MenuItem 
                            onClick={() => {
                                actCloseMainMenu()
                                actExportToUrl()
                            }}
                        >
                            {"Export to URL"->React.string}
                        </MenuItem>
                        <MenuItem 
                            onClick={() => {
                                actCloseMainMenu()
                                actExportToJson()
                            }}
                        >
                            {"Export to JSON"->React.string}
                        </MenuItem>
                        <MenuItem
                            onClick={() => {
                                actCloseMainMenu()
                                actOpenImportFromJsonDialog()
                            }}
                        >
                            {"Import from JSON ..."->React.string}
                        </MenuItem>
                        <MenuItem
                            onClick={() => {
                                actCloseMainMenu()
                                actResetEditorContent()
                            }}
                        >
                            {"Reset editor content"->React.string}
                        </MenuItem>
                        <MenuItem
                            onClick={() => {
                                actCloseMainMenu()
                                actShowCompletedProof()
                            }}
                        >
                            {"Show completed proof"->React.string}
                        </MenuItem>
                        <MenuItem
                            onClick={() => {
                                actCloseMainMenu()
                                actRenumberSteps()
                            }}
                        >
                            {"Renumber steps"->React.string}
                        </MenuItem>
                    </Menu>
                }
            }
        } else {
            React.null
        }
    }

    let rndButtons = () => {
        <Paper>
            <Row
                spacing = 0.
                childXsOffset = {idx => {
                    switch idx {
                        | 12 => Some(Js.Json.string("auto"))
                        | _ => None
                    }
                }}
            >
                <Checkbox
                    disabled=editIsActive
                    indeterminate={ mainCheckboxState->Belt_Option.isNone }
                    checked={mainCheckboxState->Belt_Option.getWithDefault(false)}
                    onChange={_ => actToggleMainCheckbox()}
                    style=?{
                        if (smallBtns) {Some(ReactDOM.Style.make(~padding="2px", ()))} else {None}
                    }
                />
                {rndIconButton(~icon=<MM_Icons.ArrowDownward/>, ~onClick=actMoveCheckedStmtsDown, ~active= !editIsActive && canMoveCheckedStmts(state,false),
                    ~title="Move selected steps down", ~smallBtns, ~notifyEditInTempMode, ())}
                {rndIconButton(~icon=<MM_Icons.ArrowUpward/>, ~onClick=actMoveCheckedStmtsUp, ~active= !editIsActive && canMoveCheckedStmts(state,true),
                    ~title="Move selected steps up", ~smallBtns, ~notifyEditInTempMode, ())}
                {rndIconButton(~icon=<MM_Icons.Add/>, ~onClick=actAddNewStmt, ~active= !editIsActive,
                    ~title="Add new step (and place before selected steps if any)", ~smallBtns, ~notifyEditInTempMode, ())}
                {rndIconButton(~icon=<MM_Icons.DeleteForever/>, ~onClick=actDeleteCheckedStmts, ~notifyEditInTempMode,
                    ~active= !editIsActive && atLeastOneStmtIsChecked, ~title="Delete selected steps", ~smallBtns, ()
                )}
                {rndIconButton(~icon=<MM_Icons.Logout style=ReactDOM.Style.make(~transform="rotate(-90deg)", ()) />, 
                    ~onClick=()=>actDuplicateStmt(true), 
                    ~active= !editIsActive && isSingleStmtChecked(state), ~title="Duplicate selected step up", 
                    ~smallBtns, ~notifyEditInTempMode, ())}
                {rndIconButton(~icon=<MM_Icons.Logout style=ReactDOM.Style.make(~transform="rotate(+90deg)", ()) />, 
                    ~onClick=()=>actDuplicateStmt(false), 
                    ~active= !editIsActive && isSingleStmtChecked(state), ~title="Duplicate selected step down", 
                    ~smallBtns, ~notifyEditInTempMode, ())}
                {rndIconButton(~icon=<MM_Icons.MergeType style=ReactDOM.Style.make(~transform="rotate(180deg)", ())/>, 
                    ~onClick=actMergeStmts, ~notifyEditInTempMode,
                    ~active= numOfCheckedStmts==1 || thereIsDuplicatedStmt, 
                    ~title="Merge two similar steps", ~smallBtns, ())}
                {rndIconButton(~icon=<MM_Icons.Restore/>, 
                    ~active= !editIsActive, ~onClick=actOpenRestorePrevStateDialog, ~notifyEditInTempMode,
                    ~title="Restore previous state", ~smallBtns, ())}
                { 
                    rndIconButton(~icon=<MM_Icons.Search/>, ~onClick=actSearchAsrt, ~notifyEditInTempMode,
                        ~active=generalModificationActionIsEnabled && state.frms->MM_substitution.frmsSize > 0,
                        ~title="Add new steps from existing assertions (and place before selected steps if any)", 
                        ~smallBtns, ()
                    ) 
                }
                { rndIconButton(~icon=<MM_Icons.TextRotationNone/>, ~onClick=actSubstitute, ~notifyEditInTempMode,
                    ~active=generalModificationActionIsEnabled,
                    ~title="Apply a substitution to all steps", ~smallBtns,() ) }
                { 
                    rndIconButton(~icon=<MM_Icons.Hub/>, ~onClick={() => actUnify(())},
                        ~active=generalModificationActionIsEnabled 
                                    && (!atLeastOneStmtIsChecked || singleProvableChecked->Belt.Option.isSome)
                                    && state.stmts->Js_array2.length > 0, 
                        ~notifyEditInTempMode=?{
                            if (singleProvableChecked->Belt.Option.isSome) {Some(notifyEditInTempMode)} else {None}
                        },
                        ~title="Unify all steps or unify selected provable bottom-up", ~smallBtns, () )
                }
                { 
                    rndIconButton(~icon=<MM_Icons.Menu/>, ~onClick=actOpenMainMenu, ~active={!editIsActive}, 
                        ~ref=ReactDOM.Ref.domRef(mainMenuButtonRef),
                        ~title="Additional actions", ~smallBtns, () )
                }
            </Row>
        </Paper>
    }

    let rndErrors = (stmt:userStmt):reElem => {
        if (stmt.stmtErr->Belt_Option.isSome 
            || stmt.syntaxErr->Belt_Option.isSome 
            || stmt.unifErr->Belt_Option.isSome) {
            <Col style=ReactDOM.Style.make(~marginLeft="10px", ())>
                {rndError(stmt.stmtErr->Belt.Option.map(err => err.msg),"red")}
                {
                    rndError(
                        stmt.syntaxErr->Belt.Option.map(msg => {
                            if (msg == "") {
                                "Syntax error."
                            } else {
                                `Syntax error - ${msg}.`
                            }
                        }),
                        "red"
                    )
                }
                {rndError(stmt.unifErr,"darkgrey")}
            </Col>
        } else {
            <></>
        }
    }

    let rndStmt = (stmt:userStmt):reElem => {
        <MM_cmp_user_stmt
            modalRef
            settingsVer=state.settingsV
            settings=state.settings
            preCtxVer=state.preCtxV
            varsText=state.varsText
            wrkCtx=state.wrkCtx
            frms=state.frms
            parenCnt=state.parenCnt
            syntaxTypes=state.syntaxTypes
            parensMap=state.parensMap
            stmt
            typeColors=state.typeColors
            preCtxColors=state.preCtxColors
            wrkCtxColors=state.wrkCtxColors
            viewOptions
            readOnly=false
            parenAc
            toggleParenAc=actToggleParenAc
            editStmtsByLeftClick=state.settings.editStmtsByLeftClick
            longClickEnabled=state.settings.longClickEnabled
            longClickDelayMs=state.settings.longClickDelayMs
            defaultStmtType=state.settings.defaultStmtType
            showVisByDefault=state.settings.showVisByDefault

            onLabelEditRequested={() => actBeginEdit(setLabelEditMode,stmt.id)}
            onLabelEditDone={newLabel => actCompleteEditLabel(stmt.id,newLabel)}
            onLabelEditCancel={newLabel => actCancelEditLabel(stmt.id,newLabel)}

            onTypEditRequested={() => actBeginEdit(setTypEditMode,stmt.id)}
            onTypEditDone={(newTyp,newIsGoal) => actCompleteEdit(
                completeTypEditMode(_,stmt.id,newTyp,newIsGoal)
            )}

            onContEditRequested={() => actBeginEdit(setContEditMode,stmt.id)}
            onContEditDone={newContText => actCompleteEdit(completeContEditMode(_,stmt.id,newContText))}
            onContEditCancel={newContText => actCancelEditCont(stmt.id,newContText)}
            onSyntaxTreeUpdated={newStmtCont => actSyntaxTreeUpdated(setStmtCont(_,stmt.id,newStmtCont))}
            
            onJstfEditRequested={() => actBeginEdit(setJstfEditMode,stmt.id)}
            onJstfEditDone={newJstf => actCompleteEdit(completeJstfEditMode(_,stmt.id,newJstf))}
            onJstfEditCancel={newJstf => actCancelEditJstf(stmt.id,newJstf)}

            checkboxDisabled=editIsActive
            checkboxChecked={state->isStmtChecked(stmt.id)}
            checkboxOnChange={_ => actToggleStmtChecked(stmt.id)}

            onGenerateProof={()=>actExportProof(stmt.id)}
            onDebug={() => notifyEditInTempMode(()=>actDebugUnifyAll(stmt.id))}

            addStmtAbove=actAddStmtAbove(stmt.id)
            addStmtBelow=actAddStmtBelow(stmt.id)
            setShowTabs
            openFrameExplorer
        />
    }

    let rndStmtAndErrors = (stmt:userStmt) => {
        <Col key=stmt.id spacing=0.>
            {rndStmt(stmt)}
            {rndErrors(stmt)}
        </Col>
    }

    let rndDescr = () => {
        <Row alignItems=#"flex-start" spacing=1. style=ReactDOM.Style.make(~marginLeft="7px", ~marginTop="12px", ())>
            <span onClick={_=>actBeginEdit0(setDescrEditMode)} style=ReactDOM.Style.make(~cursor="pointer", ())>
                {React.string("Description")}
            </span>
            <Col>
                <MM_cmp_multiline_text
                    text=state.descr
                    editMode=state.descrEditMode
                    editByClick=false
                    editByAltClick=true
                    longClickEnabled=state.settings.longClickEnabled
                    longClickDelayMs=state.settings.longClickDelayMs
                    onEditRequested={() => actBeginEdit0(setDescrEditMode)}
                    onEditDone=actDescrEditComplete
                    onEditCancel={newText => actCancelEditDescr(newText)}
                    renderer={str => {
                        <Static_XML_to_HTML xmlStr=str />
                    }}
                    fullWidth=true
                    onHelp={() => {
                        openModal(modalRef, () => React.null)->promiseMap(modalId => {
                            updateModal(modalRef, modalId, () => {
                                <XML_formatting_help onClose={_=>closeModal(modalRef, modalId)} />
                            })
                        })->ignore
                    }}
                    onDelete={() => {
                        actDescrEditComplete("")
                    }}
                />
            </Col>
        </Row>
    }

    let rndVars = () => {
        <Row alignItems=#"flex-start" spacing=1. style=ReactDOM.Style.make(~marginLeft="7px", ~marginTop="3px", ())>
            <span onClick={_=>actBeginEdit0(setVarsEditMode)} style=ReactDOM.Style.make(~cursor="pointer", ())>
                {React.string("Variables")}
            </span>
            <Col>
                <MM_cmp_multiline_text
                    text=state.varsText
                    editMode=state.varsEditMode
                    editByClick=true
                    editByAltClick=true
                    longClickEnabled=state.settings.longClickEnabled
                    longClickDelayMs=state.settings.longClickDelayMs
                    onEditRequested={() => actBeginEdit0(setVarsEditMode)}
                    onEditDone=actVarsEditComplete
                    onEditCancel={newText => actCancelEditVars(newText)}
                    onDelete={() => {
                        actVarsEditComplete("")
                    }}
                />
                {rndError(state.varsErr,"red")}
            </Col>
        </Row>
    }

    let rndDisj = () => {
        <Row alignItems=#"flex-start" spacing=1. style=ReactDOM.Style.make(~marginLeft="7px", ())>
            <span onClick={_=>actBeginEdit0(setDisjEditMode)} style=ReactDOM.Style.make(~cursor="pointer", ())>
                {React.string("Disjoints")}
            </span>
            <Col>
                <MM_cmp_multiline_text
                    text=state.disjText
                    editMode=state.disjEditMode
                    editByClick=true
                    editByAltClick=true
                    longClickEnabled=state.settings.longClickEnabled
                    longClickDelayMs=state.settings.longClickDelayMs
                    onEditRequested={() => actBeginEdit0(setDisjEditMode)}
                    onEditDone=actDisjEditComplete
                    onEditCancel={newText => actCancelEditDisj(newText)}
                    onDelete={() => {
                        actDisjEditComplete("")
                    }}
                />
                {rndError(state.disjErr,"red")}
            </Col>
        </Row>
    }

    let rndStmts = () => {
        <Col spacing=0.>
            { state.stmts->Js_array2.map(rndStmtAndErrors)->React.array }
        </Col>
    }

    <Expln_React_ContentWithStickyHeader
        top
        header={rndButtons()}
        content={_ => {
            <Col spacing=0. >
                {rndMainMenu()}
                {rndDescr()}
                {rndVars()}
                {rndDisj()}
                {rndStmts()}
            </Col>
        }}
    />
}
