open Expln_test
open MM_parser
open MM_context
open MM_wrk_ctx_data

let createMmCtx = (mmFile) => {
    let mmFileText = Expln_utils_files.readStringFromFile(mmFile)
    let (ast, _) = parseMmFile(~mmFileContent=mmFileText)
    loadContext(ast)
}

let demo0 = "./src/metamath/test/resources/demo0._mm"

describe("prepareParenInts", _ => {
    it("filters out incorrect parentheses", _ => {
        //given
        let ctx = createMmCtx(demo0)

        //when
        let parenInts = prepareParenInts(ctx, "( ) [ ]. [ ] <.| |.> { }")

        //then
        assertEq( parenInts, ctx->ctxStrToIntsExn("( ) [ ] { }") )
    })
})
