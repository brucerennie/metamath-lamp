open Expln_React_Mui
open MM_context
open MM_cmp_settings
open MM_wrk_editor
open MM_wrk_settings
open MM_substitution
open MM_parenCounter
open Expln_React_Modal
open Common
open MM_wrk_pre_ctx_data
open MM_react_common

type tabData =
    | Settings
    | Editor
    | ExplorerIndex
    | ExplorerFrame({label:string})

type state = {
    preCtxData:preCtxData
}

let createInitialState = (~settings) => {
    preCtxData: preCtxDataMake(~settings)
}

let findSyntaxTypes = (ctx:mmContext, frms: Belt_MapString.t<frmSubsData>): array<int> => {
    let syntaxTypes = Belt_HashSetInt.make(~hintSize=16)
    ctx->forEachHypothesisInDeclarationOrder(hyp => {
        if (hyp.typ == F) {
            syntaxTypes->Belt_HashSetInt.add(hyp.expr[0])
        }
        None
    })->ignore
    frms->Belt_MapString.forEach((_,frm) => {
        frm.frame.hyps->Js_array2.forEach(hyp => {
            if (hyp.typ == F) {
                syntaxTypes->Belt_HashSetInt.add(hyp.expr[0])
            }
        })
    })
    syntaxTypes->Belt_HashSetInt.toArray
}

let updatePreCtxData = (
    st:state,
    ~settings:option<settings>=?,
    ~ctx:option<(array<mmCtxSrcDto>,mmContext)>=?,
    ()
): state => {
    {
        preCtxData: st.preCtxData->preCtxDataUpdate( ~settings?, ~ctx?, () )
    }
}

@get external getClientHeight: Dom.element => int = "clientHeight"
@new external makeMutationObserver: (array<{..}> => unit) => {..} = "ResizeObserver"

let mainTheme = ThemeProvider.createTheme(
    {
        "palette": {
            "grey": {
                "main": "#e0e0e0",
            }
        }
    }
)

@new external parseUrlQuery: string => {..} = "URLSearchParams"
@val external window: {..} = "window"
@val external document: {..} = "document"

let location = window["location"]
let tempMode = ref(false)
let editorInitialStateJsonStr = switch parseUrlQuery(location["search"])["get"](. "editorState")->Js.Nullable.toOption {
    | Some(initialStateSafeBase64) => {
        window["history"]["replaceState"](. 
            "removing editorState from the URL", 
            "", 
            location["origin"] ++ location["pathname"]
        )->ignore
        tempMode := true
        Some(initialStateSafeBase64->safeBase64ToStr)
    }
    | None => Local_storage_utils.locStorReadString(MM_cmp_editor.editorStateLocStorKey)
}

if (tempMode.contents) {
    document["title"] = "TEMP " ++ document["title"]
}

@react.component
let make = () => {
    let modalRef = useModalRef()
    @warning("-27")
    let {tabs, addTab, openTab, removeTab, renderTabs, updateTabs, activeTabId} = Expln_React_UseTabs.useTabs()
    let (state, setState) = React.useState(_ => createInitialState(~settings=settingsReadFromLocStor()))

    let reloadCtx = React.useRef(Js.Nullable.null)

    let isFrameExplorerTab = (tabData:tabData, ~label:option<string>=?, ()):bool => {
        switch tabData {
            | ExplorerFrame({label:lbl}) => label->Belt_Option.mapWithDefault(true, label => lbl == label)
            | _ => false
        }
    }

    let actCloseFrmTabs = () => {
        tabs->Js.Array2.forEach(tab => {
            if (isFrameExplorerTab(tab.data, ())) {
                removeTab(tab.id)
            }
        })
    }

    let actCtxUpdated = (srcs:array<mmCtxSrcDto>, newCtx:mmContext) => {
        actCloseFrmTabs()
        setState(updatePreCtxData(_,~ctx=(srcs,newCtx), ()))
    }

    let actSettingsUpdated = (newSettings:settings) => {
        actCloseFrmTabs()
        setState(updatePreCtxData(_,~settings=newSettings, ()))
        settingsSaveToLocStor(newSettings, tempMode.contents)
    }

    let openFrameExplorer = (label:string):unit => {
        setState(st => {
            switch st.preCtxData.ctxV.val->getFrame(label) {
                | None => {
                    openInfoDialog( ~modalRef, ~text=`Cannot find an assertion by label '${label}'`, () )
                }
                | Some(_) => {
                    updateTabs(tabsSt => {
                        let tabsSt = switch tabsSt->Expln_React_UseTabs.getTabs
                                                ->Js.Array2.find(tab => isFrameExplorerTab(tab.data, ~label, ())) {
                            | Some(tab) => tabsSt->Expln_React_UseTabs.openTab(tab.id)
                            | None => {
                                let (tabsSt, tabId) = tabsSt->Expln_React_UseTabs.addTab( 
                                    ~label, ~closable=true, ~data=ExplorerFrame({label:label})
                                )
                                let tabsSt = tabsSt->Expln_React_UseTabs.openTab(tabId)
                                tabsSt
                            }
                        }
                        tabsSt
                    })
                }
            }
            st
        })
    }

    React.useEffect0(()=>{
        updateTabs(st => {
            if (st->Expln_React_UseTabs.getTabs->Js_array2.length == 0) {
                let (st, _) = st->Expln_React_UseTabs.addTab(~label="Settings", ~closable=false, ~data=Settings)
                let (st, editorTabId) = st->Expln_React_UseTabs.addTab(~label="Editor", ~closable=false, ~data=Editor)
                let (st, _) = st->Expln_React_UseTabs.addTab(~label="Explorer", ~closable=false, ~data=ExplorerIndex)
                let st = st->Expln_React_UseTabs.openTab(editorTabId)
                st
            } else {
                st
            }
        })
        None
    })

    let rndTabContent = (top:int, tab:Expln_React_UseTabs.tab<'a>) => {
        <div key=tab.id style=ReactDOM.Style.make(~display=if (tab.id == activeTabId) {"block"} else {"none"}, ())>
            {
                switch tab.data {
                    | Settings => 
                        <MM_cmp_settings 
                            modalRef
                            ctx=state.preCtxData.ctxV.val
                            settingsVer=state.preCtxData.settingsV.ver
                            settings=state.preCtxData.settingsV.val
                            onChange=actSettingsUpdated
                        />
                    | Editor => 
                        <MM_cmp_editor
                            top
                            modalRef
                            preCtxData=state.preCtxData
                            reloadCtx
                            initialStateJsonStr=editorInitialStateJsonStr
                            tempMode=tempMode.contents
                        />
                    | ExplorerIndex => 
                        <MM_cmp_pe_index
                            modalRef
                            preCtxData=state.preCtxData
                            openFrameExplorer
                        />
                    | ExplorerFrame({label}) => 
                        <MM_cmp_pe_frame_full
                            top
                            modalRef
                            preCtxData=state.preCtxData
                            label
                            openFrameExplorer
                        />
                }
            }
        </div>
    }

    <ThemeProvider theme=mainTheme>
        <Expln_React_ContentWithStickyHeader
            top=0
            header={
                <Col>
                    <MM_cmp_context_selector 
                        modalRef 
                        webSrcSettings={state.preCtxData.settingsV.val.webSrcSettings}
                        onUrlBecomesTrusted={
                            if (tempMode.contents) {
                                None
                            } else {
                                Some(url => state.preCtxData.settingsV.val->markUrlAsTrusted(url)->actSettingsUpdated)
                            }
                        }
                        onChange={(srcs,ctx)=>actCtxUpdated(srcs, ctx)}
                        reloadCtx
                        tempMode=tempMode.contents
                    />
                    {renderTabs()}
                </Col>
            }
            content={contentTop => {
                <Col>
                    {React.array(tabs->Js_array2.map(rndTabContent(contentTop, _)))}
                    <Expln_React_Modal modalRef />
                </Col>
            }}
        />
    </ThemeProvider>
}