let exn = str => Exn.raiseError(str)

@new external createArray: int => array<'a> = "Array"
let clearArray:array<'a> => unit = %raw(`arr => arr.length = 0`)
let arrFlatMap = (arr,func) => arr -> Belt.Array.map(func)->Belt.Array.concatMany
let arrStrDistinct = arr => arr->Belt_Set.String.fromArray->Belt_Set.String.toArray
let arrIntDistinct = arr => arr->Belt_Set.Int.fromArray->Belt_Set.Int.toArray
let arrForEach = (arr: array<'a>, consumer: 'a => option<'b>):option<'b> => {
    let len = arr->Array.length
    let i = ref(0)
    let res = ref(None)
    while (i.contents < len && res.contents->Belt_Option.isNone) {
        res.contents = consumer(arr->Array.getUnsafe(i.contents))
        i.contents = i.contents + 1
    }
    res.contents
}
let arrJoin = (arr:array<'a>, sep:'a):array<'a> => {
    let arrLen = arr->Array.length
    if (arrLen < 2) {
        arr
    } else {
        let res = createArray(arrLen*2-1)
        let maxI = arrLen - 1
        for i in 0 to maxI {
            res[2*i] = arr->Array.getUnsafe(i)
            if (i != maxI) {
                res[2*i+1] = sep
            }
        }
        res
    }
}

let copySubArray = (~src:array<'t>, ~srcFromIdx:int, ~dst:array<'t>, ~dstFromIdx:int, ~len:int): unit => {
    let s = ref(srcFromIdx)
    let d = ref(dstFromIdx)
    let srcLen = src->Array.length
    let dstLen = dst->Array.length
    let sMax = Math.Int.min(srcLen - 1, srcFromIdx + len - 1)
    while (s.contents <= sMax && d.contents < dstLen) {
        dst[d.contents] = src->Array.getUnsafe(s.contents)
        d.contents = d.contents + 1
        s.contents = s.contents + 1
    }
}

type comparator<'a> = ('a, 'a) => float

let toIntCmp: 'a. comparator<'a> => (('a,'a)=>int) = cmp => (a,b) => cmp(a,b)
    ->Math.sign
    ->Math.Int.floor

let intCmp: comparator<int> = (a:int, b:int) => if a < b {-1.0} else if a == b {0.0} else {1.0}
let floatCmp: comparator<float> = (a:float ,b:float) => if a < b {-1.0} else if a == b {0.0} else {1.0}
let strCmp: comparator<string> = String.localeCompare
let strCmpI: comparator<string> = (s1,s2) => strCmp(s1->String.toLocaleUpperCase ,s2->String.toLocaleUpperCase)
let cmpRev: 'a. comparator<'a> => comparator<'a> = cmp => (a,b) => -.cmp(a,b)

let stringify = (a:'a):string => switch JSON.stringifyAny(a) {
    | Some(str) => str
    | None => "undefined"
}

type explnUtilsException = {
    msg:string,
}
exception ExplnUtilsException(explnUtilsException)


let comparatorBy = (prop:'a=>int):comparator<'a> => {
    (a,b) => {
        let propA = prop(a)
        let propB = prop(b)
        if (propA < propB) {
            -1.0
        } else if (propA == propB) {
            0.0
        } else {
            1.0
        }
    }
}

let comparatorAndThen = (cmp1:comparator<'a>, cmp2:comparator<'a>):comparator<'a> => {
    (x,y) => {
        switch cmp1(x,y) {
            | 0.0 => cmp2(x,y)
            | f => f
        }
    }
}

let comparatorInverse = (cmp:comparator<'a>):comparator<'a> => (x,y) => -.cmp(x,y)

//https://stackoverflow.com/questions/7616461/generate-a-hash-from-string-in-javascript
//https://stackoverflow.com/questions/194846/is-there-hash-code-function-accepting-any-object-type
let hashStr: string => int = %raw(`
    str => {
        let hash = 0;
        for (let i = 0; i < str.length; i++) {
            hash = ( ( hash << 5 ) - hash ) + str.charCodeAt(i);
            hash |= 0;  // Convert to 32-bit integer
        }
        return hash;
    }
`)

let hashArrInt: array<int> => int = %raw(`
    arr => {
        let hash = 0;
        for (let i = 0; i < arr.length; i++) {
            hash = ( ( hash << 5 ) - hash ) + arr[i];
            hash |= 0;  // Convert to 32-bit integer
        }
        return hash;
    }
`)

let hashArrIntFromTo: (array<int>, int, int) => int = %raw(`
    (arr,from,to) => {
        let hash = 0;
        for (let i = from; i <= to; i++) {
            hash = ( ( hash << 5 ) - hash ) + arr[i];
            hash |= 0;  // Convert to 32-bit integer
        }
        return hash;
    }
`)

let hash2: (int, int) => int = %raw(`
    (a,b) => ( ( ( a << 5 ) - a ) + b ) | 0
`)

let sortInPlaceWith: 'a. (array<'a>, comparator<'a>) => array<'a> = (arr, cmp) => {
    arr->Array.sort(cmp)
    arr
}