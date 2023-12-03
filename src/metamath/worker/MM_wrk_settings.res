type typeSettings = {
    typ: string,
    color: string,
    prefix: string,
}

type webSrcSettings = {
    alias: string,
    url: string,
    trusted: bool,
}

type frameRestrict = {
    useDisc:bool,
    useDepr:bool,
    useTranDepr:bool,
}

type allowedFrms = {
    inSyntax: frameRestrict,
    inEssen: frameRestrict,
}

type settings = {
    parens: string,
    asrtsToSkip: array<string>, //deprecated

    descrRegexToDisc: string,
    labelRegexToDisc: string,
    descrRegexToDepr: string,
    labelRegexToDepr: string,
    discColor:string,
    deprColor:string,
    tranDeprColor:string,
    allowedFrms:allowedFrms,

    editStmtsByLeftClick:bool,
    defaultStmtType:string,
    defaultStmtLabel:string,
    initStmtIsGoal:bool,
    checkSyntax:bool,
    stickGoalToBottom:bool,
    autoMergeStmts:bool,
    typeSettings: array<typeSettings>,
    unifMetavarPrefix:string,
    sortDisjByType:string,
    webSrcSettings: array<webSrcSettings>,
    longClickEnabled:bool,
    longClickDelayMs:int,
    hideContextSelector:bool,
    showVisByDefault:bool,
    editorHistMaxLength:int,
    combCntMax:int,

    useDefaultTransforms:bool,
    useCustomTransforms:bool,
    customTransforms:string,
}

let markUrlAsTrusted = (settings:settings, url:string):settings => {
    if (settings.webSrcSettings->Js.Array2.find(ws => ws.url == url)->Belt.Option.isSome) {
        {
            ...settings,
            webSrcSettings: settings.webSrcSettings->Js.Array2.map(ws => {
                if (ws.url == url) {
                    {
                        ...ws,
                        trusted:true
                    }
                } else {
                    ws
                }
            })
        }
    } else {
        {
            ...settings,
            webSrcSettings: settings.webSrcSettings->Js.Array2.concat([
                {
                    alias:"",
                    url,
                    trusted:true,
                }
            ])
        }
    }
}

let settingsGetTypeColors = (settings:settings):Belt_HashMapString.t<string> => {
    settings.typeSettings
        ->Js_array2.map(ts => (ts.typ, ts.color))
        ->Belt_HashMapString.fromArray
}