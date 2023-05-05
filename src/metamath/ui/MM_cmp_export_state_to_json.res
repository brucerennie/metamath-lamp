open Expln_React_common
open Expln_React_Mui
open MM_react_common
open Local_storage_utils
open Common

@react.component
let make = (
    ~jsonStr:string, 
    ~onClose:unit=>unit
) => {
    let (appendTimestamp, setAppendTimestamp) = useStateFromLocalStorageBool("export-to-json-append-timestamp", false)
    let (copiedToClipboard, setCopiedToClipboard) = React.useState(() => None)

    let timestampStr = if (appendTimestamp) {
        Common.currTimeStr() ++ " "
    } else {
        ""
    }
    let textToShow = timestampStr ++ jsonStr

    let actCopyToClipboard = () => {
        copyToClipboard(textToShow)
        setCopiedToClipboard(timerId => {
            switch timerId {
                | None => ()
                | Some(timerId) => clearTimeout(timerId)
            }
            Some(setTimeout(
                () => setCopiedToClipboard(_ => None),
                1000
            ))
        })
    }

    <Paper style=ReactDOM.Style.make( ~padding="10px", () ) >
        <Col>
            <Row alignItems=#center>
                <FormControlLabel
                    control={
                        <Checkbox
                            checked=appendTimestamp
                            onChange={evt2bool(b => setAppendTimestamp(_ => b))}
                        />
                    }
                    label="append timestamp"
                />
                <Button onClick={_=>actCopyToClipboard()} variant=#contained style=ReactDOM.Style.make(~width="90px", ()) > 
                    {
                        if (copiedToClipboard->Belt.Option.isSome) {
                            React.string("Copied")
                        } else {
                            React.string("Copy")
                        }
                    } 
                </Button>
                <Button onClick={_=>onClose()} > {React.string("Close")} </Button>
            </Row>
            <pre style=ReactDOM.Style.make(~overflow="auto", ())>{React.string(textToShow)}</pre>
        </Col>
    </Paper>
}