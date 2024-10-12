open MM_context

type unifErr = 
    | UnifErr
    | DisjCommonVar({frmVar1:int, expr1:expr, frmVar2:int, expr2:expr, commonVar:int})
    | Disj({frmVar1:int, expr1:expr, var1:int, frmVar2:int, expr2:expr, var2:int})
    | UnprovedFloating({expr:expr})
    | NoUnifForAsrt({asrtExpr:expr, expr:expr})
    | NoUnifForArg({args:array<expr>, errArgIdx:int})
    | NewVarsAreDisabled({args:array<expr>, errArgIdx:int})
    | TooManyCombinations({frmLabels:option<array<string>>})

let argsToString = (args:array<expr>, exprToStr:expr=>string):string => {
    args->Array.mapWithIndex((arg,i) => {
        `${(i+1)->Belt.Int.toString}: ${if (arg->Array.length == 0) { "?" } else { exprToStr(arg) } }`
    })->Array.joinUnsafe("\n")
}

let unifErrToStr = (
    err:unifErr,
    ~exprToStr: expr=>string,
    ~frmExprToStr: expr=>string,
) => {

    switch err {
        | UnifErr => "Details of the error were not stored."
        | TooManyCombinations({frmLabels}) => {
            switch frmLabels {
                | None => "This assertion produces too big search space." 
                                ++ " Only part of that search space was examined."
                | Some(frmLabels) => "Some assertions produce too big search space." 
                                ++ " Only part of that search space was examined."
                                ++ " Those assertions are: " ++ frmLabels->Array.joinUnsafe(", ") ++ " ."
            }
        }
        | DisjCommonVar({frmVar1, expr1, frmVar2, expr2, commonVar}) => {
            let arrow = String.fromCharCode(8594)
            `Unsatisfied disjoint, common variable ${exprToStr([commonVar])}:\n`
                ++ `${frmExprToStr([frmVar1])} ${arrow} ${exprToStr(expr1)}\n`
                ++ `${frmExprToStr([frmVar2])} ${arrow} ${exprToStr(expr2)}`
        }
        | Disj({frmVar1, expr1, var1, frmVar2, expr2, var2}) => {
            let arrow = String.fromCharCode(8594)
            `Missing disjoint ${exprToStr([var1])},${exprToStr([var2])}:\n`
                ++ `${frmExprToStr([frmVar1])} ${arrow} ${exprToStr(expr1)}\n`
                ++ `${frmExprToStr([frmVar2])} ${arrow} ${exprToStr(expr2)}`
        }
        | UnprovedFloating({expr:expr}) => `Could not prove this floating statement:\n` ++ exprToStr(expr)
        | NoUnifForAsrt({asrtExpr, expr}) => {
            let arrow = String.fromCharCode(8594)
            `Could not find a match for assertion:\n`
                ++ `${frmExprToStr(asrtExpr)}\n${arrow}\n${exprToStr(expr)}`
        }
        | NoUnifForArg({args,errArgIdx}) => {
            let colon = if (args->Array.length == 0) {""} else {":"}
            `Could not match essential hypothesis #${(errArgIdx+1)->Belt.Int.toString}${colon}\n`
                ++ argsToString(args, exprToStr)
        }
        | NewVarsAreDisabled({args,errArgIdx}) => {
            let what = if (args->Array.length == errArgIdx) {
                "assertion"
            } else {
                `essential hypothesis #${(errArgIdx+1)->Belt.Int.toString}`
            }
            let colon = if (args->Array.length == 0) {""} else {":"}
            `New variables are not allowed, but one had to be created`
                ++ ` when unifying ${what}${colon}\n`
                ++ argsToString(args, exprToStr)
        }
    }
}