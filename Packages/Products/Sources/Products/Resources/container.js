"use strict";
(() => {
  var __defProp = Object.defineProperty;
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __publicField = (obj, key, value) => {
    __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);
    return value;
  };

  // node_modules/nanoid/url-alphabet/index.js
  var urlAlphabet = "useandom-26T198340PX75pxJACKVERYMINDBUSHWOLF_GQZbfghjklqvwyzrict";

  // node_modules/nanoid/index.browser.js
  var nanoid = (size = 21) => {
    let id2 = "";
    let bytes = crypto.getRandomValues(new Uint8Array(size |= 0));
    while (size--) {
      id2 += urlAlphabet[bytes[size] & 63];
    }
    return id2;
  };

  // node_modules/@novasamatech/host-api/dist/helpers.js
  function delay(ttl) {
    return new Promise((resolve) => setTimeout(resolve, ttl));
  }
  var promiseWithResolvers = () => {
    let resolve;
    let reject;
    const promise = new Promise((res, rej) => {
      resolve = res;
      reject = rej;
    });
    return { promise, resolve, reject };
  };
  function composeAction(method, suffix) {
    return `${method}_${suffix}`;
  }
  function createRequestId() {
    return nanoid(8);
  }

  // node_modules/neverthrow/dist/index.es.js
  var defaultErrorConfig = {
    withStackTrace: false
  };
  var createNeverThrowError = (message, result, config = defaultErrorConfig) => {
    const data = result.isOk() ? { type: "Ok", value: result.value } : { type: "Err", value: result.error };
    const maybeStack = config.withStackTrace ? new Error().stack : void 0;
    return {
      data,
      message,
      stack: maybeStack
    };
  };
  function __awaiter(thisArg, _arguments, P, generator) {
    function adopt(value) {
      return value instanceof P ? value : new P(function(resolve) {
        resolve(value);
      });
    }
    return new (P || (P = Promise))(function(resolve, reject) {
      function fulfilled(value) {
        try {
          step(generator.next(value));
        } catch (e) {
          reject(e);
        }
      }
      function rejected(value) {
        try {
          step(generator["throw"](value));
        } catch (e) {
          reject(e);
        }
      }
      function step(result) {
        result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
      }
      step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
  }
  function __values(o) {
    var s = typeof Symbol === "function" && Symbol.iterator, m = s && o[s], i = 0;
    if (m)
      return m.call(o);
    if (o && typeof o.length === "number")
      return {
        next: function() {
          if (o && i >= o.length)
            o = void 0;
          return { value: o && o[i++], done: !o };
        }
      };
    throw new TypeError(s ? "Object is not iterable." : "Symbol.iterator is not defined.");
  }
  function __await(v) {
    return this instanceof __await ? (this.v = v, this) : new __await(v);
  }
  function __asyncGenerator(thisArg, _arguments, generator) {
    if (!Symbol.asyncIterator)
      throw new TypeError("Symbol.asyncIterator is not defined.");
    var g = generator.apply(thisArg, _arguments || []), i, q = [];
    return i = Object.create((typeof AsyncIterator === "function" ? AsyncIterator : Object).prototype), verb("next"), verb("throw"), verb("return", awaitReturn), i[Symbol.asyncIterator] = function() {
      return this;
    }, i;
    function awaitReturn(f) {
      return function(v) {
        return Promise.resolve(v).then(f, reject);
      };
    }
    function verb(n, f) {
      if (g[n]) {
        i[n] = function(v) {
          return new Promise(function(a, b) {
            q.push([n, v, a, b]) > 1 || resume(n, v);
          });
        };
        if (f)
          i[n] = f(i[n]);
      }
    }
    function resume(n, v) {
      try {
        step(g[n](v));
      } catch (e) {
        settle(q[0][3], e);
      }
    }
    function step(r) {
      r.value instanceof __await ? Promise.resolve(r.value.v).then(fulfill, reject) : settle(q[0][2], r);
    }
    function fulfill(value) {
      resume("next", value);
    }
    function reject(value) {
      resume("throw", value);
    }
    function settle(f, v) {
      if (f(v), q.shift(), q.length)
        resume(q[0][0], q[0][1]);
    }
  }
  function __asyncDelegator(o) {
    var i, p;
    return i = {}, verb("next"), verb("throw", function(e) {
      throw e;
    }), verb("return"), i[Symbol.iterator] = function() {
      return this;
    }, i;
    function verb(n, f) {
      i[n] = o[n] ? function(v) {
        return (p = !p) ? { value: __await(o[n](v)), done: false } : f ? f(v) : v;
      } : f;
    }
  }
  function __asyncValues(o) {
    if (!Symbol.asyncIterator)
      throw new TypeError("Symbol.asyncIterator is not defined.");
    var m = o[Symbol.asyncIterator], i;
    return m ? m.call(o) : (o = typeof __values === "function" ? __values(o) : o[Symbol.iterator](), i = {}, verb("next"), verb("throw"), verb("return"), i[Symbol.asyncIterator] = function() {
      return this;
    }, i);
    function verb(n) {
      i[n] = o[n] && function(v) {
        return new Promise(function(resolve, reject) {
          v = o[n](v), settle(resolve, reject, v.done, v.value);
        });
      };
    }
    function settle(resolve, reject, d, v) {
      Promise.resolve(v).then(function(v2) {
        resolve({ value: v2, done: d });
      }, reject);
    }
  }
  var ResultAsync = class _ResultAsync {
    constructor(res) {
      this._promise = res;
    }
    static fromSafePromise(promise) {
      const newPromise = promise.then((value) => new Ok(value));
      return new _ResultAsync(newPromise);
    }
    static fromPromise(promise, errorFn) {
      const newPromise = promise.then((value) => new Ok(value)).catch((e) => new Err(errorFn(e)));
      return new _ResultAsync(newPromise);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    static fromThrowable(fn, errorFn) {
      return (...args) => {
        return new _ResultAsync((() => __awaiter(this, void 0, void 0, function* () {
          try {
            return new Ok(yield fn(...args));
          } catch (error) {
            return new Err(errorFn ? errorFn(error) : error);
          }
        }))());
      };
    }
    static combine(asyncResultList) {
      return combineResultAsyncList(asyncResultList);
    }
    static combineWithAllErrors(asyncResultList) {
      return combineResultAsyncListWithAllErrors(asyncResultList);
    }
    map(f) {
      return new _ResultAsync(this._promise.then((res) => __awaiter(this, void 0, void 0, function* () {
        if (res.isErr()) {
          return new Err(res.error);
        }
        return new Ok(yield f(res.value));
      })));
    }
    andThrough(f) {
      return new _ResultAsync(this._promise.then((res) => __awaiter(this, void 0, void 0, function* () {
        if (res.isErr()) {
          return new Err(res.error);
        }
        const newRes = yield f(res.value);
        if (newRes.isErr()) {
          return new Err(newRes.error);
        }
        return new Ok(res.value);
      })));
    }
    andTee(f) {
      return new _ResultAsync(this._promise.then((res) => __awaiter(this, void 0, void 0, function* () {
        if (res.isErr()) {
          return new Err(res.error);
        }
        try {
          yield f(res.value);
        } catch (e) {
        }
        return new Ok(res.value);
      })));
    }
    orTee(f) {
      return new _ResultAsync(this._promise.then((res) => __awaiter(this, void 0, void 0, function* () {
        if (res.isOk()) {
          return new Ok(res.value);
        }
        try {
          yield f(res.error);
        } catch (e) {
        }
        return new Err(res.error);
      })));
    }
    mapErr(f) {
      return new _ResultAsync(this._promise.then((res) => __awaiter(this, void 0, void 0, function* () {
        if (res.isOk()) {
          return new Ok(res.value);
        }
        return new Err(yield f(res.error));
      })));
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    andThen(f) {
      return new _ResultAsync(this._promise.then((res) => {
        if (res.isErr()) {
          return new Err(res.error);
        }
        const newValue = f(res.value);
        return newValue instanceof _ResultAsync ? newValue._promise : newValue;
      }));
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    orElse(f) {
      return new _ResultAsync(this._promise.then((res) => __awaiter(this, void 0, void 0, function* () {
        if (res.isErr()) {
          return f(res.error);
        }
        return new Ok(res.value);
      })));
    }
    match(ok2, _err) {
      return this._promise.then((res) => res.match(ok2, _err));
    }
    unwrapOr(t) {
      return this._promise.then((res) => res.unwrapOr(t));
    }
    /**
     * @deprecated will be removed in 9.0.0.
     *
     * You can use `safeTry` without this method.
     * @example
     * ```typescript
     * safeTry(async function* () {
     *   const okValue = yield* yourResult
     * })
     * ```
     * Emulates Rust's `?` operator in `safeTry`'s body. See also `safeTry`.
     */
    safeUnwrap() {
      return __asyncGenerator(this, arguments, function* safeUnwrap_1() {
        return yield __await(yield __await(yield* __asyncDelegator(__asyncValues(yield __await(this._promise.then((res) => res.safeUnwrap()))))));
      });
    }
    // Makes ResultAsync implement PromiseLike<Result>
    then(successCallback, failureCallback) {
      return this._promise.then(successCallback, failureCallback);
    }
    [Symbol.asyncIterator]() {
      return __asyncGenerator(this, arguments, function* _a() {
        const result = yield __await(this._promise);
        if (result.isErr()) {
          yield yield __await(errAsync(result.error));
        }
        return yield __await(result.value);
      });
    }
  };
  function okAsync(value) {
    return new ResultAsync(Promise.resolve(new Ok(value)));
  }
  function errAsync(err2) {
    return new ResultAsync(Promise.resolve(new Err(err2)));
  }
  var fromPromise = ResultAsync.fromPromise;
  var fromSafePromise = ResultAsync.fromSafePromise;
  var fromAsyncThrowable = ResultAsync.fromThrowable;
  var combineResultList = (resultList) => {
    let acc = ok([]);
    for (const result of resultList) {
      if (result.isErr()) {
        acc = err(result.error);
        break;
      } else {
        acc.map((list) => list.push(result.value));
      }
    }
    return acc;
  };
  var combineResultAsyncList = (asyncResultList) => ResultAsync.fromSafePromise(Promise.all(asyncResultList)).andThen(combineResultList);
  var combineResultListWithAllErrors = (resultList) => {
    let acc = ok([]);
    for (const result of resultList) {
      if (result.isErr() && acc.isErr()) {
        acc.error.push(result.error);
      } else if (result.isErr() && acc.isOk()) {
        acc = err([result.error]);
      } else if (result.isOk() && acc.isOk()) {
        acc.value.push(result.value);
      }
    }
    return acc;
  };
  var combineResultAsyncListWithAllErrors = (asyncResultList) => ResultAsync.fromSafePromise(Promise.all(asyncResultList)).andThen(combineResultListWithAllErrors);
  var Result;
  (function(Result3) {
    function fromThrowable2(fn, errorFn) {
      return (...args) => {
        try {
          const result = fn(...args);
          return ok(result);
        } catch (e) {
          return err(errorFn ? errorFn(e) : e);
        }
      };
    }
    Result3.fromThrowable = fromThrowable2;
    function combine(resultList) {
      return combineResultList(resultList);
    }
    Result3.combine = combine;
    function combineWithAllErrors(resultList) {
      return combineResultListWithAllErrors(resultList);
    }
    Result3.combineWithAllErrors = combineWithAllErrors;
  })(Result || (Result = {}));
  function ok(value) {
    return new Ok(value);
  }
  function err(err2) {
    return new Err(err2);
  }
  var Ok = class {
    constructor(value) {
      this.value = value;
    }
    isOk() {
      return true;
    }
    isErr() {
      return !this.isOk();
    }
    map(f) {
      return ok(f(this.value));
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    mapErr(_f) {
      return ok(this.value);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    andThen(f) {
      return f(this.value);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    andThrough(f) {
      return f(this.value).map((_value) => this.value);
    }
    andTee(f) {
      try {
        f(this.value);
      } catch (e) {
      }
      return ok(this.value);
    }
    orTee(_f) {
      return ok(this.value);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    orElse(_f) {
      return ok(this.value);
    }
    asyncAndThen(f) {
      return f(this.value);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    asyncAndThrough(f) {
      return f(this.value).map(() => this.value);
    }
    asyncMap(f) {
      return ResultAsync.fromSafePromise(f(this.value));
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    unwrapOr(_v) {
      return this.value;
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    match(ok2, _err) {
      return ok2(this.value);
    }
    safeUnwrap() {
      const value = this.value;
      return function* () {
        return value;
      }();
    }
    _unsafeUnwrap(_) {
      return this.value;
    }
    _unsafeUnwrapErr(config) {
      throw createNeverThrowError("Called `_unsafeUnwrapErr` on an Ok", this, config);
    }
    // eslint-disable-next-line @typescript-eslint/no-this-alias, require-yield
    *[Symbol.iterator]() {
      return this.value;
    }
  };
  var Err = class {
    constructor(error) {
      this.error = error;
    }
    isOk() {
      return false;
    }
    isErr() {
      return !this.isOk();
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    map(_f) {
      return err(this.error);
    }
    mapErr(f) {
      return err(f(this.error));
    }
    andThrough(_f) {
      return err(this.error);
    }
    andTee(_f) {
      return err(this.error);
    }
    orTee(f) {
      try {
        f(this.error);
      } catch (e) {
      }
      return err(this.error);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    andThen(_f) {
      return err(this.error);
    }
    // eslint-disable-next-line @typescript-eslint/no-explicit-any, @typescript-eslint/explicit-module-boundary-types
    orElse(f) {
      return f(this.error);
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    asyncAndThen(_f) {
      return errAsync(this.error);
    }
    asyncAndThrough(_f) {
      return errAsync(this.error);
    }
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    asyncMap(_f) {
      return errAsync(this.error);
    }
    unwrapOr(v) {
      return v;
    }
    match(_ok, err2) {
      return err2(this.error);
    }
    safeUnwrap() {
      const error = this.error;
      return function* () {
        yield err(error);
        throw new Error("Do not use this generator out of `safeTry`");
      }();
    }
    _unsafeUnwrap(config) {
      throw createNeverThrowError("Called `_unsafeUnwrap` on an Err", this, config);
    }
    _unsafeUnwrapErr(_) {
      return this.error;
    }
    *[Symbol.iterator]() {
      const self = this;
      yield self;
      return self;
    }
  };
  var fromThrowable = Result.fromThrowable;

  // node_modules/scale-ts/dist/scale-ts.js
  var __defProp2 = Object.defineProperty;
  var __defNormalProp2 = (obj, key, value) => key in obj ? __defProp2(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __publicField2 = (obj, key, value) => {
    __defNormalProp2(obj, typeof key !== "symbol" ? key + "" : key, value);
    return value;
  };
  var HEX_MAP = {
    0: 0,
    1: 1,
    2: 2,
    3: 3,
    4: 4,
    5: 5,
    6: 6,
    7: 7,
    8: 8,
    9: 9,
    a: 10,
    b: 11,
    c: 12,
    d: 13,
    e: 14,
    f: 15,
    A: 10,
    B: 11,
    C: 12,
    D: 13,
    E: 14,
    F: 15
  };
  function fromHex(hexString) {
    const isOdd = hexString.length % 2;
    const base = (hexString[1] === "x" ? 2 : 0) + isOdd;
    const nBytes = (hexString.length - base) / 2 + isOdd;
    const bytes = new Uint8Array(nBytes);
    if (isOdd)
      bytes[0] = 0 | HEX_MAP[hexString[2]];
    for (let i = 0; i < nBytes; ) {
      const idx = base + i * 2;
      const a = HEX_MAP[hexString[idx]];
      const b = HEX_MAP[hexString[idx + 1]];
      bytes[isOdd + i++] = a << 4 | b;
    }
    return bytes;
  }
  var InternalUint8Array = class extends Uint8Array {
    constructor(buffer) {
      super(buffer);
      __publicField2(this, "i", 0);
      __publicField2(this, "v");
      this.v = new DataView(buffer);
    }
  };
  var toInternalBytes = (fn) => (buffer) => fn(buffer instanceof InternalUint8Array ? buffer : new InternalUint8Array(buffer instanceof Uint8Array ? buffer.buffer : typeof buffer === "string" ? fromHex(buffer).buffer : buffer));
  var mergeUint8 = (inputs) => {
    const len = inputs.length;
    let totalLen = 0;
    for (let i = 0; i < len; i++)
      totalLen += inputs[i].length;
    const result = new Uint8Array(totalLen);
    for (let idx = 0, at = 0; idx < len; idx++) {
      const current = inputs[idx];
      result.set(current, at);
      at += current.byteLength;
    }
    return result;
  };
  function mapObject(input, mapper) {
    const keys = Object.keys(input);
    const len = keys.length;
    const result = {};
    for (let i = 0; i < len; i++) {
      const key = keys[i];
      result[key] = mapper(input[key], key);
    }
    return result;
  }
  var createCodec = (encoder, decoder) => {
    const result = [encoder, decoder];
    result.enc = encoder;
    result.dec = decoder;
    return result;
  };
  var enhanceEncoder = (encoder, mapper) => (value) => encoder(mapper(value));
  var enhanceDecoder = (decoder, mapper) => (value) => mapper(decoder(value));
  var enhanceCodec = ([encoder, decoder], toFrom, fromTo) => createCodec(enhanceEncoder(encoder, toFrom), enhanceDecoder(decoder, fromTo));
  function decodeInt(nBytes, getter) {
    return toInternalBytes((bytes) => {
      const result = bytes.v[getter](bytes.i, true);
      bytes.i += nBytes;
      return result;
    });
  }
  function encodeInt(nBytes, setter) {
    return (input) => {
      const result = new Uint8Array(nBytes);
      const dv = new DataView(result.buffer);
      dv[setter](0, input, true);
      return result;
    };
  }
  function intCodec(nBytes, getter, setter) {
    return createCodec(encodeInt(nBytes, setter), decodeInt(nBytes, getter));
  }
  var u8 = intCodec(1, "getUint8", "setUint8");
  var u16 = intCodec(2, "getUint16", "setUint16");
  var u32 = intCodec(4, "getUint32", "setUint32");
  var u64 = intCodec(8, "getBigUint64", "setBigUint64");
  var i8 = intCodec(1, "getInt8", "setInt8");
  var i16 = intCodec(2, "getInt16", "setInt16");
  var i32 = intCodec(4, "getInt32", "setInt32");
  var i64 = intCodec(8, "getBigInt64", "setBigInt64");
  var x128Enc = (value) => {
    const result = new Uint8Array(16);
    const dv = new DataView(result.buffer);
    dv.setBigInt64(0, value, true);
    dv.setBigInt64(8, value >> 64n, true);
    return result;
  };
  var create128Dec = (method) => toInternalBytes((input) => {
    const { v, i } = input;
    const right = v.getBigUint64(i, true);
    const left = v[method](i + 8, true);
    input.i += 16;
    return left << 64n | right;
  });
  var u128 = createCodec(x128Enc, create128Dec("getBigUint64"));
  var i128 = createCodec(x128Enc, create128Dec("getBigInt64"));
  var x256Enc = (value) => {
    const result = new Uint8Array(32);
    const dv = new DataView(result.buffer);
    dv.setBigInt64(0, value, true);
    dv.setBigInt64(8, value >> 64n, true);
    dv.setBigInt64(16, value >> 128n, true);
    dv.setBigInt64(24, value >> 192n, true);
    return result;
  };
  var create256Dec = (method) => toInternalBytes((input) => {
    let result = input.v.getBigUint64(input.i, true);
    input.i += 8;
    result |= input.v.getBigUint64(input.i, true) << 64n;
    input.i += 8;
    result |= input.v.getBigUint64(input.i, true) << 128n;
    input.i += 8;
    result |= input.v[method](input.i, true) << 192n;
    input.i += 8;
    return result;
  });
  var u256 = createCodec(x256Enc, create256Dec("getBigUint64"));
  var i256 = createCodec(x256Enc, create256Dec("getBigInt64"));
  var bool = enhanceCodec(u8, (value) => value ? 1 : 0, Boolean);
  var decoders = [u8[1], u16[1], u32[1]];
  var compactDec = toInternalBytes((bytes) => {
    const init = bytes[bytes.i];
    const kind = init & 3;
    if (kind < 3)
      return decoders[kind](bytes) >>> 2;
    const nBytes = (init >>> 2) + 4;
    bytes.i++;
    let result = 0n;
    const nU64 = nBytes / 8 | 0;
    let shift = 0n;
    for (let i = 0; i < nU64; i++) {
      result = u64[1](bytes) << shift | result;
      shift += 64n;
    }
    let nReminders = nBytes % 8;
    if (nReminders > 3) {
      result = BigInt(u32[1](bytes)) << shift | result;
      shift += 32n;
      nReminders -= 4;
    }
    if (nReminders > 1) {
      result = BigInt(u16[1](bytes)) << shift | result;
      shift += 16n;
      nReminders -= 2;
    }
    if (nReminders)
      result = BigInt(u8[1](bytes)) << shift | result;
    return result;
  });
  var MIN_U64 = 1n << 56n;
  var MIN_U32 = 1 << 24;
  var MIN_U16 = 256;
  var U32_MASK = 4294967295n;
  var SINGLE_BYTE_MODE_LIMIT = 1 << 6;
  var TWO_BYTE_MODE_LIMIT = 1 << 14;
  var FOUR_BYTE_MODE_LIMIT = 1 << 30;
  var compactEnc = (input) => {
    if (input < 0)
      throw new Error(`Wrong compact input (${input})`);
    const nInput = Number(input) << 2;
    if (input < SINGLE_BYTE_MODE_LIMIT)
      return u8[0](nInput);
    if (input < TWO_BYTE_MODE_LIMIT)
      return u16[0](nInput | 1);
    if (input < FOUR_BYTE_MODE_LIMIT)
      return u32[0](nInput | 2);
    let buffers = [new Uint8Array(1)];
    let bigValue = BigInt(input);
    while (bigValue >= MIN_U64) {
      buffers.push(u64[0](bigValue));
      bigValue >>= 64n;
    }
    if (bigValue >= MIN_U32) {
      buffers.push(u32[0](Number(bigValue & U32_MASK)));
      bigValue >>= 32n;
    }
    let smValue = Number(bigValue);
    if (smValue >= MIN_U16) {
      buffers.push(u16[0](smValue));
      smValue >>= 16;
    }
    smValue && buffers.push(u8[0](smValue));
    const result = mergeUint8(buffers);
    result[0] = result.length - 5 << 2 | 3;
    return result;
  };
  var compact = createCodec(compactEnc, compactDec);
  var textEncoder = new TextEncoder();
  var strEnc = (str2) => {
    const val = textEncoder.encode(str2);
    return mergeUint8([compact.enc(val.length), val]);
  };
  var textDecoder = new TextDecoder();
  var strDec = toInternalBytes((bytes) => {
    let nElements = compact.dec(bytes);
    const dv = new DataView(bytes.buffer, bytes.i, nElements);
    bytes.i += nElements;
    return textDecoder.decode(dv);
  });
  var str = createCodec(strEnc, strDec);
  var noop = () => {
  };
  var emptyArr = new Uint8Array(0);
  var _void = createCodec(() => emptyArr, noop);
  var BytesEnc = (nBytes) => nBytes === void 0 ? (bytes) => mergeUint8([compact.enc(bytes.length), bytes]) : (bytes) => bytes.length === nBytes ? bytes : bytes.slice(0, nBytes);
  var BytesDec = (nBytes) => toInternalBytes((bytes) => {
    const len = nBytes === void 0 ? compact.dec(bytes) : nBytes !== Infinity ? nBytes : bytes.byteLength - bytes.i;
    const result = new Uint8Array(bytes.buffer.slice(bytes.i, bytes.i + len));
    bytes.i += len;
    return result;
  });
  var Bytes = (nBytes) => createCodec(BytesEnc(nBytes), BytesDec(nBytes));
  Bytes.enc = BytesEnc;
  Bytes.dec = BytesDec;
  var enumEnc = (inner, x) => {
    const keys = Object.keys(inner);
    const mappedKeys = new Map(x?.map((actualIdx, idx) => [keys[idx], actualIdx]) ?? keys.map((key, idx) => [key, idx]));
    const getKey = (key) => mappedKeys.get(key);
    return ({ tag, value }) => mergeUint8([u8.enc(getKey(tag)), inner[tag](value)]);
  };
  var enumDec = (inner, x) => {
    const keys = Object.keys(inner);
    const mappedKeys = new Map(x?.map((actualIdx, idx) => [actualIdx, keys[idx]]) ?? keys.map((key, idx) => [idx, key]));
    return toInternalBytes((bytes) => {
      const idx = u8.dec(bytes);
      const tag = mappedKeys.get(idx);
      const innerDecoder = inner[tag];
      return {
        tag,
        value: innerDecoder(bytes)
      };
    });
  };
  var Enum = (inner, ...args) => createCodec(enumEnc(mapObject(inner, ([encoder]) => encoder), ...args), enumDec(mapObject(inner, ([, decoder]) => decoder), ...args));
  Enum.enc = enumEnc;
  Enum.dec = enumDec;
  var OptionDec = (inner) => toInternalBytes((bytes) => u8[1](bytes) > 0 ? inner(bytes) : void 0);
  var OptionEnc = (inner) => (value) => {
    const result = new Uint8Array(1);
    if (value === void 0)
      return result;
    result[0] = 1;
    return mergeUint8([result, inner(value)]);
  };
  var Option = (inner) => createCodec(OptionEnc(inner[0]), OptionDec(inner[1]));
  Option.enc = OptionEnc;
  Option.dec = OptionDec;
  var ResultDec = (okDecoder, koDecoder) => toInternalBytes((bytes) => {
    const success = u8[1](bytes) === 0;
    const decoder = success ? okDecoder : koDecoder;
    const value = decoder(bytes);
    return { success, value };
  });
  var ResultEnc = (okEncoder, koEncoder) => ({ success, value }) => mergeUint8([
    u8[0](success ? 0 : 1),
    (success ? okEncoder : koEncoder)(value)
  ]);
  var Result2 = (okCodec, koCodec) => createCodec(ResultEnc(okCodec[0], koCodec[0]), ResultDec(okCodec[1], koCodec[1]));
  Result2.dec = ResultDec;
  Result2.enc = ResultEnc;
  var TupleDec = (...decoders2) => toInternalBytes((bytes) => decoders2.map((decoder) => decoder(bytes)));
  var TupleEnc = (...encoders) => (values) => mergeUint8(encoders.map((enc, idx) => enc(values[idx])));
  var Tuple = (...codecs) => createCodec(TupleEnc(...codecs.map(([encoder]) => encoder)), TupleDec(...codecs.map(([, decoder]) => decoder)));
  Tuple.enc = TupleEnc;
  Tuple.dec = TupleDec;
  var StructEnc = (encoders) => {
    const keys = Object.keys(encoders);
    return enhanceEncoder(Tuple.enc(...Object.values(encoders)), (input) => keys.map((k) => input[k]));
  };
  var StructDec = (decoders2) => {
    const keys = Object.keys(decoders2);
    return enhanceDecoder(Tuple.dec(...Object.values(decoders2)), (tuple) => Object.fromEntries(tuple.map((value, idx) => [keys[idx], value])));
  };
  var Struct = (codecs) => createCodec(StructEnc(mapObject(codecs, (x) => x[0])), StructDec(mapObject(codecs, (x) => x[1])));
  Struct.enc = StructEnc;
  Struct.dec = StructDec;
  var VectorEnc = (inner, size) => size >= 0 ? (value) => mergeUint8(value.map(inner)) : (value) => mergeUint8([compact.enc(value.length), mergeUint8(value.map(inner))]);
  var VectorDec = (getter, size) => toInternalBytes((bytes) => {
    const nElements = size >= 0 ? size : compact.dec(bytes);
    const result = new Array(nElements);
    for (let i = 0; i < nElements; i++) {
      result[i] = getter(bytes);
    }
    return result;
  });
  var Vector = (inner, size) => createCodec(VectorEnc(inner[0], size), VectorDec(inner[1], size));
  Vector.enc = VectorEnc;
  Vector.dec = VectorDec;

  // node_modules/@novasamatech/scale/dist/lazy.js
  function lazy(fn) {
    return createCodec((v) => fn().enc(v), (v) => fn().dec(v));
  }

  // node_modules/@polkadot-api/utils/dist/hex.js
  var HEX_STR = "0123456789abcdef";
  function toHex(bytes) {
    const result = new Array(bytes.length + 1);
    result[0] = "0x";
    for (let i = 0; i < bytes.length; ) {
      const b = bytes[i++];
      result[i] = HEX_STR[b >> 4] + HEX_STR[b & 15];
    }
    return result.join("");
  }
  var HEX_MAP2 = {
    0: 0,
    1: 1,
    2: 2,
    3: 3,
    4: 4,
    5: 5,
    6: 6,
    7: 7,
    8: 8,
    9: 9,
    a: 10,
    b: 11,
    c: 12,
    d: 13,
    e: 14,
    f: 15,
    A: 10,
    B: 11,
    C: 12,
    D: 13,
    E: 14,
    F: 15
  };
  function fromHex2(hexString) {
    const isOdd = hexString.length % 2;
    const base = (hexString[1] === "x" ? 2 : 0) + isOdd;
    const nBytes = (hexString.length - base) / 2 + isOdd;
    const bytes = new Uint8Array(nBytes);
    if (isOdd)
      bytes[0] = 0 | HEX_MAP2[hexString[2]];
    for (let i = 0; i < nBytes; ) {
      const idx = base + i * 2;
      const a = HEX_MAP2[hexString[idx]];
      const b = HEX_MAP2[hexString[idx + 1]];
      bytes[isOdd + i++] = a << 4 | b;
    }
    return bytes;
  }

  // node_modules/@polkadot-api/utils/dist/noop.js
  var noop2 = Function.prototype;

  // node_modules/@polkadot-api/utils/dist/AbortError.js
  var AbortError = class extends Error {
    constructor() {
      super("Abort Error");
      this.name = "AbortError";
    }
  };

  // node_modules/@novasamatech/scale/dist/hex.js
  var Hex = (length) => enhanceCodec(Bytes(length), fromHex2, (v) => toHex(v));

  // node_modules/@novasamatech/scale/dist/nullable.js
  function Nullable(inner) {
    return enhanceCodec(Option(inner), (v) => v === null ? void 0 : v, (v) => v === void 0 ? null : v);
  }

  // node_modules/@novasamatech/scale/dist/optionBool.js
  var OptionBool = enhanceCodec(u8, (value) => {
    if (value === void 0) {
      return 0;
    }
    return value ? 1 : 2;
  }, (v) => {
    switch (v) {
      case 0:
        return void 0;
      case 1:
        return true;
      case 2:
        return false;
      default:
        throw new Error(`Unknown value for optionBool: ${v}. Should be ether 0, 1 or 2.`);
    }
  });

  // node_modules/@novasamatech/scale/dist/status.js
  function Status(...list) {
    return enhanceCodec(u8, (v) => {
      const i = list.indexOf(v);
      if (i === -1) {
        throw new Error(`Unknown status value: ${v}`);
      }
      return i;
    }, (i) => {
      const v = list.at(i);
      if (v === void 0) {
        throw new Error(`Unknown status index: ${i}`);
      }
      return v;
    });
  }

  // node_modules/@novasamatech/scale/dist/enum.js
  var Enum2 = (inner, indexes) => Enum(inner, indexes);

  // node_modules/@novasamatech/scale/dist/err.js
  function Err2(name, value, message, className = name) {
    const C = {
      [className]: class extends Error {
        constructor(data) {
          super(typeof message === "function" ? message(data) : message);
          __publicField(this, "instance", className);
          __publicField(this, "name", name);
          __publicField(this, "payload");
          this.payload = data;
        }
        get value() {
          return this.payload;
        }
        // codec array destructuring workaround
        static [Symbol.iterator]() {
          return errorCodec[Symbol.iterator]();
        }
        // codec fields access workaround
        get enc() {
          return errorCodec.enc;
        }
        get dec() {
          return errorCodec.dec;
        }
      }
    }[className];
    const errorCodec = enhanceCodec(
      value,
      (v) => v.payload,
      // @ts-expect-error don't want to fix it really
      (v) => new C(v)
    );
    return Object.assign(C, errorCodec);
  }

  // node_modules/@novasamatech/scale/dist/errEnum.js
  function ErrEnum(name, inner) {
    const variants = Object.fromEntries(Object.entries(inner).map(([k, [value, message]]) => [k, Err2(`${name}::${k}`, value, message, k)]));
    const codec = enhanceCodec(Enum2(variants), (v) => ({ tag: v.instance, value: v }), (v) => v.value);
    const result = Object.assign(codec, variants);
    Object.defineProperty(result, Symbol.hasInstance, {
      value: (v) => Object.values(variants).some((C) => v instanceof C)
    });
    return result;
  }

  // node_modules/@novasamatech/scale/dist/helpers.js
  function resultOk(value) {
    return { success: true, value };
  }
  function resultErr(e) {
    return { success: false, value: e };
  }
  function enumValue(tag, value) {
    return { tag, value };
  }
  function isEnumVariant(v, tag) {
    return v.tag === tag;
  }
  function toHex2(data) {
    return toHex(data);
  }
  function fromHex3(hex) {
    return fromHex2(hex);
  }

  // node_modules/@novasamatech/host-api/dist/protocol/commonCodecs.js
  var GenesisHash = Hex();
  var GenericErr = Struct({
    reason: str
  });
  var GenericError = Err2("GenericError", GenericErr, ({ reason }) => `Unknown error: ${reason}`);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/accounts.js
  var AccountId = Bytes(32);
  var PublicKey = Bytes();
  var DotNsIdentifier = str;
  var DerivationIndex = u32;
  var ProductAccountId = Tuple(DotNsIdentifier, DerivationIndex);
  var RingVrfProof = Bytes();
  var RingVrgAlias = Bytes();
  var ProductAccount = Struct({
    publicKey: PublicKey
  });
  var LegacyAccount = Struct({
    publicKey: PublicKey,
    name: Option(str)
  });
  var UserIdentity = Struct({
    primaryUsername: DotNsIdentifier
  });
  var ContextualAlias = Struct({
    context: Bytes(32),
    alias: RingVrgAlias
  });
  var RingLocationHint = Struct({
    palletInstance: Option(u32)
  });
  var RingLocation = Struct({
    genesisHash: GenesisHash,
    ringRootHash: Hex(),
    hints: Option(RingLocationHint)
  });
  var RequestCredentialsErr = ErrEnum("RequestCredentialsErr", {
    NotConnected: [_void, "RequestCredentials: not connected"],
    Rejected: [_void, "RequestCredentials: rejected"],
    DomainNotValid: [_void, "RequestCredentials: domain not valid"],
    Unknown: [GenericErr, "RequestCredentials: unknown error"]
  });
  var CreateProofErr = ErrEnum("CreateProofErr", {
    RingNotFound: [_void, "CreateProof: ring not found"],
    Rejected: [_void, "CreateProof: rejected"],
    Unknown: [GenericErr, "CreateProof: unknown error"]
  });
  var GetUserIdErr = ErrEnum("GetUserIdErr", {
    PermissionDenied: [_void, "GetUserId: permission denied"],
    NotConnected: [_void, "GetUserId: not connected"],
    Unknown: [GenericErr, "GetUserId: unknown error"]
  });
  var AccountConnectionStatus = Status("disconnected", "connected");
  var AccountConnectionStatusV1_start = _void;
  var AccountConnectionStatusV1_receive = AccountConnectionStatus;
  var AccountConnectionStatusV1_interrupt = _void;
  var GetUserIdV1_request = _void;
  var GetUserIdV1_response = Result2(UserIdentity, GetUserIdErr);
  var AccountGetV1_request = ProductAccountId;
  var AccountGetV1_response = Result2(ProductAccount, RequestCredentialsErr);
  var AccountGetAliasV1_request = ProductAccountId;
  var AccountGetAliasV1_response = Result2(ContextualAlias, RequestCredentialsErr);
  var AccountCreateProofV1_request = Tuple(ProductAccountId, RingLocation, Bytes());
  var AccountCreateProofV1_response = Result2(RingVrfProof, CreateProofErr);
  var GetLegacyAccountsV1_request = _void;
  var GetLegacyAccountsV1_response = Result2(Vector(LegacyAccount), RequestCredentialsErr);
  var LoginResult = Status("success", "alreadyConnected", "rejected");
  var LoginErr = ErrEnum("LoginErr", {
    Unknown: [GenericErr, "Login: unknown error"]
  });
  var RequestLoginV1_request = Option(str);
  var RequestLoginV1_response = Result2(LoginResult, LoginErr);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/customRenderer.js
  var Size = compact;
  var Dimensions = Tuple(Size, Size, Option(Size), Option(Size));
  var TypographyStyle = Status("headline.large", "title.medium.regular", "body.large.regular", "body.medium.regular", "body.small.regular");
  var ButtonVariant = Status("primary", "secondary", "text");
  var ColorToken = Status("fg.primary", "fg.secondary", "fg.tertiary", "bg.surface.main", "bg.surface.container", "bg.surface.nested", "fg.success", "fg.error", "fg.warning");
  var ContentAlignment = Status("topStart", "topCenter", "topEnd", "centerStart", "center", "centerEnd", "bottomStart", "bottomCenter", "bottomEnd");
  var HorizontalAlignment = Status("start", "center", "end");
  var VerticalAlignment = Status("top", "center", "bottom");
  var Arrangement = Status("start", "end", "center", "spaceBetween", "spaceAround", "spaceEvenly");
  var Shape = Enum2({
    Rounded: Size,
    Circle: _void
  });
  var BorderStyle = Struct({
    width: Size,
    color: ColorToken,
    shape: Option(Shape)
  });
  var Modifier = Enum2({
    margin: Dimensions,
    padding: Dimensions,
    background: Struct({
      color: ColorToken,
      shape: Option(Shape)
    }),
    border: BorderStyle,
    height: Size,
    width: Size,
    minWidth: Size,
    minHeight: Size,
    fillWidth: bool,
    fillHeight: bool
  });
  var Children = lazy(() => CustomRendererNode);
  function Component(props) {
    return Struct({
      modifiers: Vector(Modifier),
      props,
      children: Vector(Children)
    });
  }
  var BoxProps = Struct({
    contentAlignment: Option(ContentAlignment)
  });
  var ColumnProps = Struct({
    horizontalAlignment: Option(HorizontalAlignment),
    verticalArrangement: Option(Arrangement)
  });
  var RowProps = Struct({
    verticalAlignment: Option(VerticalAlignment),
    horizontalArrangement: Option(Arrangement)
  });
  var TextProps = Struct({
    style: Option(TypographyStyle),
    color: Option(ColorToken)
  });
  var ButtonProps = Struct({
    text: str,
    variant: Option(ButtonVariant),
    enabled: OptionBool,
    loading: OptionBool,
    clickAction: Option(str)
  });
  var TextFieldProps = Struct({
    text: str,
    placeholder: Option(str),
    label: Option(str),
    enabled: OptionBool,
    valueChangeAction: Option(str)
  });
  var CustomRendererNode = Enum2({
    Nil: _void,
    String: str,
    Box: Component(BoxProps),
    Column: Component(ColumnProps),
    Row: Component(RowProps),
    Spacer: Component(_void),
    Text: Component(TextProps),
    Button: Component(ButtonProps),
    TextField: Component(TextFieldProps)
  });

  // node_modules/@novasamatech/host-api/dist/protocol/v1/chat.js
  var ChatRoomRegistrationErr = ErrEnum("ChatRoomRegistrationErr", {
    PermissionDenied: [_void, "Permission denied"],
    Unknown: [GenericErr, "Unknown error while chat registration"]
  });
  var ChatRoomRequest = Struct({
    roomId: str,
    name: str,
    icon: str
    // URL or base64-encoded image for contact
  });
  var ChatRoomRegistrationStatus = Status("New", "Exists");
  var ChatRoomRegistrationResult = Struct({
    status: ChatRoomRegistrationStatus
  });
  var ChatCreateRoomV1_request = ChatRoomRequest;
  var ChatCreateRoomV1_response = Result2(ChatRoomRegistrationResult, ChatRoomRegistrationErr);
  var ChatBotRegistrationErr = ErrEnum("ChatBotRegistrationErr", {
    PermissionDenied: [_void, "Permission denied"],
    Unknown: [GenericErr, "Unknown error while chat registration"]
  });
  var ChatBotRequest = Struct({
    botId: str,
    name: str,
    icon: str
    // URL or base64-encoded image for contact
  });
  var ChatBotRegistrationStatus = Status("New", "Exists");
  var ChatBotRegistrationResult = Struct({
    status: ChatBotRegistrationStatus
  });
  var ChatRegisterBotV1_request = ChatBotRequest;
  var ChatRegisterBotV1_response = Result2(ChatBotRegistrationResult, ChatBotRegistrationErr);
  var ChatRoomParticipation = Status("RoomHost", "Bot");
  var ChatRoom = Struct({
    roomId: str,
    participatingAs: ChatRoomParticipation
  });
  var ChatListSubscribeV1_start = _void;
  var ChatListSubscribeV1_receive = Vector(ChatRoom);
  var ChatListSubscribeV1_interrupt = _void;
  var ChatAction = Struct({
    actionId: str,
    title: str
  });
  var ChatActionLayout = Status("Column", "Grid");
  var ChatActions = Struct({
    text: Option(str),
    actions: Vector(ChatAction),
    layout: ChatActionLayout
  });
  var ChatMedia = Struct({
    url: str
  });
  var ChatRichText = Struct({
    text: Option(str),
    media: Vector(ChatMedia)
  });
  var ChatFile = Struct({
    url: str,
    fileName: str,
    mimeType: str,
    sizeBytes: u64,
    text: Option(str)
  });
  var ChatReaction = Struct({
    messageId: str,
    emoji: str
  });
  var ChatCustomMessage = Struct({
    messageType: str,
    payload: Bytes()
  });
  var ChatMessageContent = Enum2({
    Text: str,
    RichText: ChatRichText,
    Actions: ChatActions,
    File: ChatFile,
    Reaction: ChatReaction,
    ReactionRemoved: ChatReaction,
    Custom: ChatCustomMessage
  });
  var ChatMessagePostingErr = ErrEnum("ChatMessagePostingErr", {
    MessageTooLarge: [_void, "ChatMessagePosting: message too large"],
    Unknown: [GenericErr, "ChatMessagePosting: unknown error"]
  });
  var ChatPostMessageResult = Struct({
    messageId: str
  });
  var ChatPostMessageV1_request = Struct({
    roomId: str,
    payload: ChatMessageContent
  });
  var ChatPostMessageV1_response = Result2(ChatPostMessageResult, ChatMessagePostingErr);
  var ActionTrigger = Struct({
    messageId: str,
    actionId: str,
    payload: Option(Bytes())
  });
  var ChatCommand = Struct({
    command: str,
    payload: str
  });
  var ChatActionPayload = Enum2({
    MessagePosted: ChatMessageContent,
    ActionTriggered: ActionTrigger,
    Command: ChatCommand
  });
  var ReceivedChatAction = Struct({
    roomId: str,
    peer: str,
    payload: ChatActionPayload
  });
  var ChatActionSubscribeV1_start = _void;
  var ChatActionSubscribeV1_receive = ReceivedChatAction;
  var ChatActionSubscribeV1_interrupt = _void;
  var ChatCustomMessageRenderingV1_start = Struct({ messageId: str, messageType: str, payload: Bytes() });
  var ChatCustomMessageRenderingV1_receive = CustomRendererNode;
  var ChatCustomMessageRenderingV1_interrupt = _void;

  // node_modules/@novasamatech/host-api/dist/protocol/v1/createTransaction.js
  var CreateTransactionErr = ErrEnum("CreateTransactionErr", {
    FailedToDecode: [_void, "Failed to decode"],
    Rejected: [_void, "Rejected"],
    // Unsupported payload version
    // Failed to infer missing extensions, some extension is unsupported, etc.
    NotSupported: [str, "Not Supported"],
    PermissionDenied: [_void, "Permission denied"],
    Unknown: [GenericErr, "Unknown error"]
  });
  var TxPayloadExtensionV1 = Struct({
    /** Identifier as defined in metadata (e.g., "CheckSpecVersion", "ChargeAssetTxPayment"). */
    id: str,
    /**
     * Explicit "extra" to sign (goes into the extrinsic body).
     * SCALE-encoded per the extension's "extra" type as defined in the metadata.
     */
    extra: Bytes(),
    /**
     * "Implicit" data to sign (known by the chain, not included into the extrinsic body).
     * SCALE-encoded per the extension's "additionalSigned" type as defined in the metadata.
     */
    additionalSigned: Bytes()
  });
  function GenericTxPayloadV1(signer) {
    return Struct({
      signer,
      /**
       * Chain identifier where transaction will be executed
       */
      genesisHash: Bytes(32),
      /**
       * SCALE-encoded Call (module indicator + function indicator + params).
       */
      callData: Bytes(),
      /**
       * Transaction extensions supplied by the caller (order irrelevant).
       * The consumer SHOULD provide every extension that is relevant to them.
       * The implementer MAY infer missing ones.
       */
      extensions: Vector(TxPayloadExtensionV1),
      /**
       * Transaction Extension Version.
       * - For Extrinsic V4 MUST be 0.
       * - For Extrinsic V5, set to any version supported by the runtime.
       * The implementer:
       *  - MUST use this field to determine the required extensions for creating the extrinsic.
       *  - MAY use this field to infer missing extensions that the implementer could know how to handle.
       */
      txExtVersion: u8
    });
  }
  var ProductAccountTransaction = GenericTxPayloadV1(ProductAccountId);
  var LegacyTransaction = GenericTxPayloadV1(AccountId);
  var CreateTransactionV1_request = ProductAccountTransaction;
  var CreateTransactionV1_response = Result2(Bytes(), CreateTransactionErr);
  var CreateTransactionWithLegacyAccountV1_request = LegacyTransaction;
  var CreateTransactionWithLegacyAccountV1_response = Result2(Bytes(), CreateTransactionErr);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/deriveEntropy.js
  var DeriveEntropyErr = ErrEnum("DeriveEntropyErr", {
    Unknown: [GenericErr, "Unknown derive entropy error"]
  });
  var Entropy = Bytes(32);
  var DeriveEntropyV1_request = Bytes();
  var DeriveEntropyV1_response = Result2(Entropy, DeriveEntropyErr);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/handshake.js
  var HandshakeErr = ErrEnum("HandshakeErr", {
    Timeout: [_void, "Handshake: timeout"],
    UnsupportedProtocolVersion: [_void, "Handshake: unsupported protocol version"],
    Unknown: [GenericErr, "Handshake: unknown error"]
  });
  var HandshakeV1_request = u8;
  var HandshakeV1_response = Result2(_void, HandshakeErr);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/localStorage.js
  var StorageErr = ErrEnum("StorageErr", {
    Full: [_void, "Storage is full"],
    Unknown: [GenericErr, "Unknown storage error"]
  });
  var StorageKey = str;
  var StorageValue = Bytes();
  var StorageReadV1_request = StorageKey;
  var StorageReadV1_response = Result2(Option(StorageValue), StorageErr);
  var StorageWriteV1_request = Tuple(StorageKey, StorageValue);
  var StorageWriteV1_response = Result2(_void, StorageErr);
  var StorageClearV1_request = StorageKey;
  var StorageClearV1_response = Result2(_void, StorageErr);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/navigation.js
  var NavigateToErr = ErrEnum("NavigateToErr", {
    PermissionDenied: [_void, "Permission denied"],
    Unknown: [GenericErr, "Unknown error"]
  });
  var NavigateToV1_request = str;
  var NavigateToV1_response = Result2(_void, NavigateToErr);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/notification.js
  var NotificationId = u32;
  var PushNotification = Struct({
    text: str,
    deeplink: Option(str),
    scheduledAt: Option(u64)
  });
  var PushNotificationError2 = ErrEnum("PushNotificationError", {
    ScheduleLimitReached: [_void, "Schedule limit reached"],
    Unknown: [GenericErr, "Unknown error"]
  });
  var PushNotificationV1_request = PushNotification;
  var PushNotificationV1_response = Result2(NotificationId, PushNotificationError2);
  var PushNotificationCancelV1_request = NotificationId;
  var PushNotificationCancelV1_response = Result2(_void, GenericError);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/payments.js
  var Sr25519SecretKey = Bytes(64);
  var PaymentId = str;
  var CoinPaymentPurseId = u32;
  var PaymentTopUpSource = Enum2({
    ProductAccount: DerivationIndex,
    PrivateKey: Sr25519SecretKey,
    Coins: Vector(Sr25519SecretKey)
  });
  var PaymentBalance = Struct({
    available: u128
  });
  var PaymentReceipt = Struct({
    id: PaymentId
  });
  var PaymentStatus = Enum2({
    Processing: _void,
    Completed: _void,
    Failed: str
  });
  var PaymentBalanceErr = ErrEnum("PaymentBalanceErr", {
    PermissionDenied: [_void, "permission denied"],
    Unknown: [GenericErr, "unknown error"]
  });
  var PartialPaymentErr = Struct({
    credited: u128
  });
  var PaymentTopUpErr = ErrEnum("PaymentTopUpErr", {
    InsufficientFunds: [_void, "insufficient funds"],
    InvalidSource: [_void, "invalid source"],
    PartialPayment: [PartialPaymentErr, ({ credited }) => `partial payment: credited ${credited}`],
    Unknown: [GenericErr, "unknown error"]
  });
  var PaymentRequestErr = ErrEnum("PaymentRequestErr", {
    Rejected: [_void, "rejected"],
    InsufficientBalance: [_void, "insufficient balance"],
    Unknown: [GenericErr, "unknown error"]
  });
  var PaymentStatusErr = ErrEnum("PaymentStatusErr", {
    PaymentNotFound: [_void, "payment not found"],
    Unknown: [GenericErr, "unknown error"]
  });
  var PaymentBalanceSubscribeV1_start = Struct({
    purse: Option(CoinPaymentPurseId)
  });
  var PaymentBalanceSubscribeV1_receive = PaymentBalance;
  var PaymentBalanceSubscribeV1_interrupt = PaymentBalanceErr;
  var PaymentTopUpV1_request = Struct({
    into: Option(CoinPaymentPurseId),
    amount: u128,
    source: PaymentTopUpSource
  });
  var PaymentTopUpV1_response = Result2(_void, PaymentTopUpErr);
  var PaymentRequestV1_request = Struct({
    from: Option(CoinPaymentPurseId),
    amount: u128,
    destination: Bytes(32)
  });
  var PaymentRequestV1_response = Result2(PaymentReceipt, PaymentRequestErr);
  var PaymentStatusSubscribeV1_start = PaymentId;
  var PaymentStatusSubscribeV1_receive = PaymentStatus;
  var PaymentStatusSubscribeV1_interrupt = PaymentStatusErr;

  // node_modules/@novasamatech/host-api/dist/protocol/v1/preimage.js
  var PreimageKey = Hex();
  var PreimageValue = Bytes();
  var PreimageLookupSubscribeV1_start = PreimageKey;
  var PreimageLookupSubscribeV1_receive = Nullable(PreimageValue);
  var PreimageLookupSubscribeV1_interrupt = _void;
  var PreimageSubmitErr = ErrEnum("PreimageSubmitErr", {
    Unknown: [GenericErr, "Unknown error"]
  });
  var PreimageSubmitV1_request = PreimageValue;
  var PreimageSubmitV1_response = Result2(PreimageKey, PreimageSubmitErr);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/resourceAllocation.js
  var AllocatableResource = Enum2({
    StatementStoreAllowance: _void,
    BulletinAllowance: _void,
    SmartContractAllowance: DerivationIndex,
    AutoSigning: _void
  });
  var AllocationOutcome = Enum2({
    Allocated: _void,
    Rejected: _void,
    NotAvailable: _void
  });
  var ResourceAllocationErr = ErrEnum("ResourceAllocationErr", {
    Unknown: [GenericErr, "ResourceAllocation: unknown error"]
  });
  var RequestResourceAllocationV1_request = Vector(AllocatableResource);
  var RequestResourceAllocationV1_response = Result2(Vector(AllocationOutcome), ResourceAllocationErr);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/sign.js
  var SigningErr = ErrEnum("SigningErr", {
    FailedToDecode: [_void, "Failed to decode"],
    Rejected: [_void, "Rejected"],
    PermissionDenied: [_void, "Permission denied"],
    Unknown: [GenericErr, ({ reason }) => reason || "Unknown error"]
  });
  var SigningResult = Struct({
    signature: Hex(),
    signedTransaction: Option(Hex())
  });
  var RawPayload = Enum2({
    Bytes: Bytes(),
    Payload: str
  });
  var SigningRawPayload = Struct({
    account: ProductAccountId,
    payload: RawPayload
  });
  var SigningRawPayloadWithoutAccount = Struct({
    signer: str,
    payload: RawPayload
  });
  var SignRawV1_request = SigningRawPayload;
  var SignRawV1_response = Result2(SigningResult, SigningErr);
  var SignRawWithLegacyAccountV1_request = SigningRawPayloadWithoutAccount;
  var SignRawWithLegacyAccountV1_response = Result2(SigningResult, SigningErr);
  var SigningPayloadPayload = Struct({
    blockHash: Hex(),
    blockNumber: Hex(),
    era: Hex(),
    genesisHash: GenesisHash,
    method: Hex(),
    nonce: Hex(),
    specVersion: Hex(),
    tip: Hex(),
    transactionVersion: Hex(),
    signedExtensions: Vector(str),
    version: u32,
    assetId: Option(Hex()),
    metadataHash: Option(Hex()),
    mode: Option(u32),
    withSignedTransaction: Option(bool)
  });
  var SigningPayload = Struct({
    account: ProductAccountId,
    payload: SigningPayloadPayload
  });
  var SigningPayloadWithoutAccount = Struct({
    signer: str,
    payload: SigningPayloadPayload
  });
  var SignPayloadV1_request = SigningPayload;
  var SignPayloadV1_response = Result2(SigningResult, SigningErr);
  var SignPayloadWithLegacyAccountV1_request = SigningPayloadWithoutAccount;
  var SignPayloadWithLegacyAccountV1_response = Result2(SigningResult, SigningErr);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/statementStore.js
  var Topic = Bytes(32);
  var Channel = Bytes(32);
  var DecryptionKey = Bytes(32);
  var Sr25519StatementProof = Struct({
    signature: Bytes(64),
    signer: Bytes(32)
  });
  var Ed25519StatementProof = Struct({
    signature: Bytes(64),
    signer: Bytes(32)
  });
  var EcdsaStatementProof = Struct({
    signature: Bytes(65),
    signer: Bytes(33)
  });
  var OnChainStatementProof = Struct({
    who: Bytes(32),
    blockHash: Bytes(32),
    event: u64
  });
  var StatementProof = Enum2({
    Sr25519: Sr25519StatementProof,
    Ed25519: Ed25519StatementProof,
    Ecdsa: EcdsaStatementProof,
    OnChain: OnChainStatementProof
  });
  var Statement = Struct({
    proof: Option(StatementProof),
    decryptionKey: Option(DecryptionKey),
    expiry: Option(u64),
    channel: Option(Channel),
    topics: Vector(Topic),
    data: Option(Bytes())
  });
  var SignedStatement = Struct({
    proof: StatementProof,
    decryptionKey: Option(DecryptionKey),
    expiry: Option(u64),
    channel: Option(Channel),
    topics: Vector(Topic),
    data: Option(Bytes())
  });
  var TopicFilter = Enum2({
    MatchAll: Vector(Topic),
    MatchAny: Vector(Topic)
  });
  var SignedStatementsPage = Struct({
    statements: Vector(SignedStatement),
    isComplete: bool
  });
  var StatementStoreSubscribeV1_start = TopicFilter;
  var StatementStoreSubscribeV1_receive = SignedStatementsPage;
  var StatementStoreSubscribeV1_interrupt = _void;
  var StatementProofErr = ErrEnum("StatementProofErr", {
    UnableToSign: [_void, "StatementProof: unable to sign"],
    UnknownAccount: [_void, "StatementProof: unknown account"],
    Unknown: [GenericErr, "StatementProof: unknown error"]
  });
  var StatementStoreCreateProofV1_request = Tuple(ProductAccountId, Statement);
  var StatementStoreCreateProofV1_response = Result2(StatementProof, StatementProofErr);
  var StatementStoreCreateProofAuthorizedV1_request = Statement;
  var StatementStoreCreateProofAuthorizedV1_response = Result2(StatementProof, StatementProofErr);
  var StatementStoreSubmitV1_request = SignedStatement;
  var StatementStoreSubmitV1_response = Result2(_void, GenericError);

  // node_modules/nanoevents/index.js
  var createNanoEvents = () => ({
    emit(event, ...args) {
      for (let callbacks = this.events[event] || [], i = 0, length = callbacks.length; i < length; i++) {
        callbacks[i](...args);
      }
    },
    events: {},
    on(event, cb) {
      var _a;
      ;
      ((_a = this.events)[event] || (_a[event] = [])).push(cb);
      return () => {
        this.events[event] = this.events[event]?.filter((i) => cb !== i);
      };
    }
  });

  // node_modules/@novasamatech/host-api/dist/constants.js
  var SCALE_CODEC_PROTOCOL_ID = 1;
  var HANDSHAKE_INTERVAL = 50;
  var HANDSHAKE_TIMEOUT = 1e4;

  // node_modules/@novasamatech/host-api/dist/protocol/v1/chainInteraction.js
  var BlockHash = Hex();
  var OperationId = str;
  var RuntimeApi = Tuple(str, u32);
  var RuntimeSpec = Struct({
    specName: str,
    implName: str,
    specVersion: u32,
    implVersion: u32,
    transactionVersion: Option(u32),
    apis: Vector(RuntimeApi)
  });
  var RuntimeType = Enum2({
    Valid: RuntimeSpec,
    Invalid: Struct({ error: str })
  });
  var StorageQueryType = Status("Value", "Hash", "ClosestDescendantMerkleValue", "DescendantsValues", "DescendantsHashes");
  var StorageQueryItem = Struct({
    key: Hex(),
    queryType: StorageQueryType
  });
  var StorageResultItem = Struct({
    key: Hex(),
    value: Nullable(Hex()),
    hash: Nullable(Hex()),
    closestDescendantMerkleValue: Nullable(Hex())
  });
  var OperationStartedResult = Enum2({
    Started: Struct({ operationId: OperationId }),
    LimitReached: _void
  });
  var ChainHeadFollowV1_start = Struct({
    genesisHash: GenesisHash,
    withRuntime: bool
  });
  var ChainHeadEvent = Enum2({
    Initialized: Struct({
      finalizedBlockHashes: Vector(BlockHash),
      finalizedBlockRuntime: Option(RuntimeType)
    }),
    NewBlock: Struct({
      blockHash: BlockHash,
      parentBlockHash: BlockHash,
      newRuntime: Option(RuntimeType)
    }),
    BestBlockChanged: Struct({
      bestBlockHash: BlockHash
    }),
    Finalized: Struct({
      finalizedBlockHashes: Vector(BlockHash),
      prunedBlockHashes: Vector(BlockHash)
    }),
    OperationBodyDone: Struct({
      operationId: OperationId,
      value: Vector(Hex())
    }),
    OperationCallDone: Struct({
      operationId: OperationId,
      output: Hex()
    }),
    OperationStorageItems: Struct({
      operationId: OperationId,
      items: Vector(StorageResultItem)
    }),
    OperationStorageDone: Struct({
      operationId: OperationId
    }),
    OperationWaitingForContinue: Struct({
      operationId: OperationId
    }),
    OperationInaccessible: Struct({
      operationId: OperationId
    }),
    OperationError: Struct({
      operationId: OperationId,
      error: str
    }),
    Stop: _void
  });
  var ChainHeadFollowV1_receive = ChainHeadEvent;
  var ChainHeadFollowV1_interrupt = _void;
  var ChainHeadHeaderV1_request = Struct({
    genesisHash: GenesisHash,
    followSubscriptionId: str,
    hash: BlockHash
  });
  var ChainHeadHeaderV1_response = Result2(Nullable(Hex()), GenericError);
  var ChainHeadBodyV1_request = Struct({
    genesisHash: GenesisHash,
    followSubscriptionId: str,
    hash: BlockHash
  });
  var ChainHeadBodyV1_response = Result2(OperationStartedResult, GenericError);
  var ChainHeadStorageV1_request = Struct({
    genesisHash: GenesisHash,
    followSubscriptionId: str,
    hash: BlockHash,
    items: Vector(StorageQueryItem),
    childTrie: Nullable(Hex())
  });
  var ChainHeadStorageV1_response = Result2(OperationStartedResult, GenericError);
  var ChainHeadCallV1_request = Struct({
    genesisHash: GenesisHash,
    followSubscriptionId: str,
    hash: BlockHash,
    function: str,
    callParameters: Hex()
  });
  var ChainHeadCallV1_response = Result2(OperationStartedResult, GenericError);
  var ChainHeadUnpinV1_request = Struct({
    genesisHash: GenesisHash,
    followSubscriptionId: str,
    hashes: Vector(BlockHash)
  });
  var ChainHeadUnpinV1_response = Result2(_void, GenericError);
  var ChainHeadContinueV1_request = Struct({
    genesisHash: GenesisHash,
    followSubscriptionId: str,
    operationId: OperationId
  });
  var ChainHeadContinueV1_response = Result2(_void, GenericError);
  var ChainHeadStopOperationV1_request = Struct({
    genesisHash: GenesisHash,
    followSubscriptionId: str,
    operationId: OperationId
  });
  var ChainHeadStopOperationV1_response = Result2(_void, GenericError);
  var ChainSpecGenesisHashV1_request = GenesisHash;
  var ChainSpecGenesisHashV1_response = Result2(Hex(), GenericError);
  var ChainSpecChainNameV1_request = GenesisHash;
  var ChainSpecChainNameV1_response = Result2(str, GenericError);
  var ChainSpecPropertiesV1_request = GenesisHash;
  var ChainSpecPropertiesV1_response = Result2(str, GenericError);
  var TransactionBroadcastV1_request = Struct({
    genesisHash: GenesisHash,
    transaction: Hex()
  });
  var TransactionBroadcastV1_response = Result2(Nullable(str), GenericError);
  var TransactionStopV1_request = Struct({
    genesisHash: GenesisHash,
    operationId: str
  });
  var TransactionStopV1_response = Result2(_void, GenericError);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/devicePermission.js
  var DevicePermission = Status("Notifications", "Camera", "Microphone", "Bluetooth", "NFC", "Location", "Clipboard", "OpenUrl", "Biometrics");
  var DevicePermissionV1_request = DevicePermission;
  var DevicePermissionV1_response = Result2(bool, GenericError);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/feature.js
  var Feature = Enum2({
    Chain: GenesisHash
  });
  var FeatureV1_request = Feature;
  var FeatureV1_response = Result2(bool, GenericError);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/remotePermission.js
  var RemotePermission = Enum2({
    Remote: Vector(str),
    WebRtc: _void,
    ChainSubmit: _void,
    PreimageSubmit: _void,
    StatementSubmit: _void
  });
  var RemotePermissionV1_request = RemotePermission;
  var RemotePermissionV1_response = Result2(bool, GenericError);

  // node_modules/@novasamatech/host-api/dist/protocol/v1/theme.js
  var ThemeName = Enum2({
    Custom: str,
    Default: _void
  });
  var ThemeVariant = Status("Light", "Dark");
  var Theme = Struct({
    name: ThemeName,
    variant: ThemeVariant
  });
  var ThemeSubscribeV1_start = _void;
  var ThemeSubscribeV1_receive = Theme;
  var ThemeSubscribeV1_interrupt = _void;

  // node_modules/@novasamatech/host-api/dist/protocol/impl.js
  var enumFromArg = (enumValues, n) => {
    return Enum2(Object.fromEntries(Object.entries(enumValues).map(([key, value]) => [key, value[n]])));
  };
  var versionedRequest = (index, values) => {
    return {
      method: "request",
      index,
      request: enumFromArg(values, 0),
      response: enumFromArg(values, 1)
    };
  };
  var versionedSubscription = (index, values) => {
    return {
      method: "subscribe",
      index,
      start: enumFromArg(values, 0),
      receive: enumFromArg(values, 1),
      interrupt: enumFromArg(values, 2)
    };
  };
  function createIndexer() {
    let offset = 0;
    const take = (width, prefix = 0) => {
      const index = offset;
      offset += prefix + width;
      return prefix + index;
    };
    return {
      request: (prefix) => take(2, prefix),
      subscription: (prefix) => take(4, prefix)
    };
  }
  var indexer = createIndexer();
  var hostApiProtocol = {
    host_handshake: versionedRequest(indexer.request(), {
      v1: [HandshakeV1_request, HandshakeV1_response]
    }),
    host_feature_supported: versionedRequest(indexer.request(), {
      v1: [FeatureV1_request, FeatureV1_response]
    }),
    host_push_notification: versionedRequest(indexer.request(), {
      v1: [PushNotificationV1_request, PushNotificationV1_response]
    }),
    host_navigate_to: versionedRequest(indexer.request(), {
      v1: [NavigateToV1_request, NavigateToV1_response]
    }),
    host_device_permission: versionedRequest(indexer.request(), {
      v1: [DevicePermissionV1_request, DevicePermissionV1_response]
    }),
    remote_permission: versionedRequest(indexer.request(), {
      v1: [RemotePermissionV1_request, RemotePermissionV1_response]
    }),
    host_local_storage_read: versionedRequest(indexer.request(), {
      v1: [StorageReadV1_request, StorageReadV1_response]
    }),
    host_local_storage_write: versionedRequest(indexer.request(), {
      v1: [StorageWriteV1_request, StorageWriteV1_response]
    }),
    host_local_storage_clear: versionedRequest(indexer.request(), {
      v1: [StorageClearV1_request, StorageClearV1_response]
    }),
    host_account_connection_status_subscribe: versionedSubscription(indexer.subscription(), {
      v1: [AccountConnectionStatusV1_start, AccountConnectionStatusV1_receive, AccountConnectionStatusV1_interrupt]
    }),
    host_account_get: versionedRequest(indexer.request(), {
      v1: [AccountGetV1_request, AccountGetV1_response]
    }),
    host_account_get_alias: versionedRequest(indexer.request(), {
      v1: [AccountGetAliasV1_request, AccountGetAliasV1_response]
    }),
    host_account_create_proof: versionedRequest(indexer.request(), {
      v1: [AccountCreateProofV1_request, AccountCreateProofV1_response]
    }),
    host_get_legacy_accounts: versionedRequest(indexer.request(), {
      v1: [GetLegacyAccountsV1_request, GetLegacyAccountsV1_response]
    }),
    host_create_transaction: versionedRequest(indexer.request(), {
      v1: [CreateTransactionV1_request, CreateTransactionV1_response]
    }),
    host_create_transaction_with_legacy_account: versionedRequest(indexer.request(), {
      v1: [CreateTransactionWithLegacyAccountV1_request, CreateTransactionWithLegacyAccountV1_response]
    }),
    host_sign_raw_with_legacy_account: versionedRequest(indexer.request(), {
      v1: [SignRawWithLegacyAccountV1_request, SignRawWithLegacyAccountV1_response]
    }),
    host_sign_payload_with_legacy_account: versionedRequest(indexer.request(), {
      v1: [SignPayloadWithLegacyAccountV1_request, SignPayloadWithLegacyAccountV1_response]
    }),
    host_chat_create_room: versionedRequest(indexer.request(), {
      v1: [ChatCreateRoomV1_request, ChatCreateRoomV1_response]
    }),
    host_chat_register_bot: versionedRequest(indexer.request(), {
      v1: [ChatRegisterBotV1_request, ChatRegisterBotV1_response]
    }),
    host_chat_list_subscribe: versionedSubscription(indexer.subscription(), {
      v1: [ChatListSubscribeV1_start, ChatListSubscribeV1_receive, ChatListSubscribeV1_interrupt]
    }),
    host_chat_post_message: versionedRequest(indexer.request(), {
      v1: [ChatPostMessageV1_request, ChatPostMessageV1_response]
    }),
    host_chat_action_subscribe: versionedSubscription(indexer.subscription(), {
      v1: [ChatActionSubscribeV1_start, ChatActionSubscribeV1_receive, ChatActionSubscribeV1_interrupt]
    }),
    product_chat_custom_message_render_subscribe: versionedSubscription(indexer.subscription(), {
      v1: [
        ChatCustomMessageRenderingV1_start,
        ChatCustomMessageRenderingV1_receive,
        ChatCustomMessageRenderingV1_interrupt
      ]
    }),
    remote_statement_store_subscribe: versionedSubscription(indexer.subscription(), {
      v1: [StatementStoreSubscribeV1_start, StatementStoreSubscribeV1_receive, StatementStoreSubscribeV1_interrupt]
    }),
    remote_statement_store_create_proof: versionedRequest(indexer.request(), {
      v1: [StatementStoreCreateProofV1_request, StatementStoreCreateProofV1_response]
    }),
    remote_statement_store_submit: versionedRequest(indexer.request(), {
      v1: [StatementStoreSubmitV1_request, StatementStoreSubmitV1_response]
    }),
    remote_preimage_lookup_subscribe: versionedSubscription(indexer.subscription(), {
      v1: [PreimageLookupSubscribeV1_start, PreimageLookupSubscribeV1_receive, PreimageLookupSubscribeV1_interrupt]
    }),
    remote_preimage_submit: versionedRequest(indexer.request(), {
      v1: [PreimageSubmitV1_request, PreimageSubmitV1_response]
    }),
    remote_chain_head_follow_subscribe: versionedSubscription(indexer.subscription(6), {
      v1: [ChainHeadFollowV1_start, ChainHeadFollowV1_receive, ChainHeadFollowV1_interrupt]
    }),
    remote_chain_head_header: versionedRequest(indexer.request(), {
      v1: [ChainHeadHeaderV1_request, ChainHeadHeaderV1_response]
    }),
    remote_chain_head_body: versionedRequest(indexer.request(), {
      v1: [ChainHeadBodyV1_request, ChainHeadBodyV1_response]
    }),
    remote_chain_head_storage: versionedRequest(indexer.request(), {
      v1: [ChainHeadStorageV1_request, ChainHeadStorageV1_response]
    }),
    remote_chain_head_call: versionedRequest(indexer.request(), {
      v1: [ChainHeadCallV1_request, ChainHeadCallV1_response]
    }),
    remote_chain_head_unpin: versionedRequest(indexer.request(), {
      v1: [ChainHeadUnpinV1_request, ChainHeadUnpinV1_response]
    }),
    remote_chain_head_continue: versionedRequest(indexer.request(), {
      v1: [ChainHeadContinueV1_request, ChainHeadContinueV1_response]
    }),
    remote_chain_head_stop_operation: versionedRequest(indexer.request(), {
      v1: [ChainHeadStopOperationV1_request, ChainHeadStopOperationV1_response]
    }),
    remote_chain_spec_genesis_hash: versionedRequest(indexer.request(), {
      v1: [ChainSpecGenesisHashV1_request, ChainSpecGenesisHashV1_response]
    }),
    remote_chain_spec_chain_name: versionedRequest(indexer.request(), {
      v1: [ChainSpecChainNameV1_request, ChainSpecChainNameV1_response]
    }),
    remote_chain_spec_properties: versionedRequest(indexer.request(), {
      v1: [ChainSpecPropertiesV1_request, ChainSpecPropertiesV1_response]
    }),
    remote_chain_transaction_broadcast: versionedRequest(indexer.request(), {
      v1: [TransactionBroadcastV1_request, TransactionBroadcastV1_response]
    }),
    remote_chain_transaction_stop: versionedRequest(indexer.request(), {
      v1: [TransactionStopV1_request, TransactionStopV1_response]
    }),
    host_theme_subscribe: versionedSubscription(indexer.subscription(), {
      v1: [ThemeSubscribeV1_start, ThemeSubscribeV1_receive, ThemeSubscribeV1_interrupt]
    }),
    host_derive_entropy: versionedRequest(indexer.request(), {
      v1: [DeriveEntropyV1_request, DeriveEntropyV1_response]
    }),
    host_get_user_id: versionedRequest(indexer.request(), {
      v1: [GetUserIdV1_request, GetUserIdV1_response]
    }),
    host_request_login: versionedRequest(indexer.request(), {
      v1: [RequestLoginV1_request, RequestLoginV1_response]
    }),
    host_sign_raw: versionedRequest(indexer.request(), {
      v1: [SignRawV1_request, SignRawV1_response]
    }),
    host_sign_payload: versionedRequest(indexer.request(), {
      v1: [SignPayloadV1_request, SignPayloadV1_response]
    }),
    host_payment_balance_subscribe: versionedSubscription(indexer.subscription(), {
      v1: [PaymentBalanceSubscribeV1_start, PaymentBalanceSubscribeV1_receive, PaymentBalanceSubscribeV1_interrupt]
    }),
    host_payment_top_up: versionedRequest(indexer.request(), {
      v1: [PaymentTopUpV1_request, PaymentTopUpV1_response]
    }),
    host_payment_request: versionedRequest(indexer.request(), {
      v1: [PaymentRequestV1_request, PaymentRequestV1_response]
    }),
    host_payment_status_subscribe: versionedSubscription(indexer.subscription(), {
      v1: [PaymentStatusSubscribeV1_start, PaymentStatusSubscribeV1_receive, PaymentStatusSubscribeV1_interrupt]
    }),
    host_request_resource_allocation: versionedRequest(indexer.request(), {
      v1: [RequestResourceAllocationV1_request, RequestResourceAllocationV1_response]
    }),
    remote_statement_store_create_proof_authorized: versionedRequest(indexer.request(), {
      v1: [StatementStoreCreateProofAuthorizedV1_request, StatementStoreCreateProofAuthorizedV1_response]
    }),
    host_push_notification_cancel: versionedRequest(indexer.request(), {
      v1: [PushNotificationCancelV1_request, PushNotificationCancelV1_response]
    })
  };

  // node_modules/@novasamatech/host-api/dist/protocol/messageCodec.js
  var createPayload = (hostApi) => {
    const fields = {};
    const indexes = [];
    for (const [method, payload] of Object.entries(hostApi)) {
      if (payload.method === "request") {
        fields[`${method}_request`] = payload.request;
        indexes.push(payload.index);
        fields[`${method}_response`] = payload.response;
        indexes.push(payload.index + 1);
      }
      if (payload.method === "subscribe") {
        fields[`${method}_start`] = payload.start;
        indexes.push(payload.index);
        fields[`${method}_stop`] = _void;
        indexes.push(payload.index + 1);
        fields[`${method}_interrupt`] = payload.interrupt;
        indexes.push(payload.index + 2);
        fields[`${method}_receive`] = payload.receive;
        indexes.push(payload.index + 3);
      }
    }
    return Enum2(fields, indexes);
  };
  var MessagePayload = createPayload(hostApiProtocol);
  var Message = Struct({
    requestId: str,
    payload: MessagePayload
  });

  // node_modules/@novasamatech/host-api/dist/transport.js
  function isConnected(status) {
    return status === "connected";
  }
  function getSubscriptionKey(method, payload) {
    return `${method}_${toHex2(MessagePayload.enc(payload))}`;
  }
  function createMessageProvider(provider) {
    const subscribers2 = /* @__PURE__ */ new Set();
    let unsubscribeProvider = null;
    return {
      postMessage(message) {
        provider.postMessage(Message.enc(message));
      },
      subscribe(fn) {
        if (subscribers2.size === 0) {
          unsubscribeProvider = provider.subscribe((payload) => {
            try {
              const message = Message.dec(payload);
              for (const subscriber of subscribers2) {
                subscriber(message);
              }
            } catch (e) {
              provider.logger.error("Transport error", e);
            }
          });
        }
        subscribers2.add(fn);
        return () => {
          subscribers2.delete(fn);
          if (subscribers2.size === 0 && unsubscribeProvider) {
            unsubscribeProvider();
            unsubscribeProvider = null;
          }
        };
      }
    };
  }
  function createTransport(provider) {
    let codecVersion = SCALE_CODEC_PROTOCOL_ID;
    const handshakeAbortController = new AbortController();
    let handshakePromise = null;
    let connectionStatusResolved = false;
    let connectionStatus = "disconnected";
    let disposed = false;
    const events = createNanoEvents();
    events.on("connectionStatus", (value) => {
      connectionStatus = value;
    });
    function changeConnectionStatus(status) {
      events.emit("connectionStatus", status);
    }
    function throwIfDisposed() {
      if (disposed) {
        throw new Error("Transport is disposed");
      }
    }
    function throwIfIncorrectEnvironment() {
      if (!provider.isCorrectEnvironment()) {
        throw new Error("Environment is not correct");
      }
    }
    function throwIfInvalidCodecVersion() {
      if (codecVersion !== SCALE_CODEC_PROTOCOL_ID) {
        throw new Error(`Unsupported codec version: ${codecVersion}`);
      }
    }
    function checks() {
      throwIfDisposed();
      throwIfIncorrectEnvironment();
      throwIfInvalidCodecVersion();
    }
    const messageProvider = createMessageProvider(provider);
    const activeSubscriptions = /* @__PURE__ */ new Map();
    let debugListenerCount = 0;
    let debugProviderUnsubscribe = null;
    function ensureDebugProviderSubscription() {
      if (debugProviderUnsubscribe)
        return;
      debugProviderUnsubscribe = messageProvider.subscribe((message) => {
        events.emit("debugMessage", {
          direction: "incoming",
          requestId: message.requestId,
          payload: message.payload
        });
      });
    }
    function maybeDisposeDebugProviderSubscription() {
      if (debugListenerCount > 0)
        return;
      debugProviderUnsubscribe?.();
      debugProviderUnsubscribe = null;
    }
    const transport = {
      provider,
      isCorrectEnvironment() {
        return provider.isCorrectEnvironment();
      },
      isReady() {
        checks();
        if (connectionStatusResolved) {
          return Promise.resolve(isConnected(connectionStatus));
        }
        if (handshakePromise) {
          return handshakePromise;
        }
        changeConnectionStatus("connecting");
        const performHandshake = () => {
          const id2 = createRequestId();
          let resolved = false;
          const cleanup = (interval, unsubscribe) => {
            clearInterval(interval);
            unsubscribe();
            handshakeAbortController.signal.removeEventListener("abort", unsubscribe);
          };
          return new Promise((resolve) => {
            const unsubscribe = transport.listenMessages("host_handshake_response", (responseId) => {
              if (responseId === id2) {
                cleanup(interval, unsubscribe);
                resolved = true;
                resolve(true);
              }
            });
            handshakeAbortController.signal.addEventListener("abort", unsubscribe, { once: true });
            const interval = setInterval(() => {
              if (handshakeAbortController.signal.aborted) {
                clearInterval(interval);
                resolve(false);
                return;
              }
              transport.postMessage(id2, enumValue("host_handshake_request", enumValue("v1", codecVersion)));
            }, HANDSHAKE_INTERVAL);
          }).then((success) => {
            if (!success && !resolved) {
              handshakeAbortController.abort("Timeout");
            }
            return success;
          });
        };
        const timedOutRequest = Promise.race([performHandshake(), delay(HANDSHAKE_TIMEOUT).then(() => false)]);
        handshakePromise = timedOutRequest.then((result) => {
          handshakePromise = null;
          connectionStatusResolved = true;
          changeConnectionStatus(result ? "connected" : "disconnected");
          return result;
        });
        return handshakePromise;
      },
      async request(method, payload, signal) {
        checks();
        if (!await transport.isReady()) {
          throw new Error("Polkadot host is not ready");
        }
        signal?.throwIfAborted();
        const requestId = createRequestId();
        const requestAction = composeAction(method, "request");
        const responseAction = composeAction(method, "response");
        const { resolve, reject, promise } = promiseWithResolvers();
        const cleanup = () => {
          unsubscribe();
          signal?.removeEventListener("abort", onAbort);
        };
        const onAbort = () => {
          cleanup();
          reject(signal?.reason ?? new Error("Request aborted"));
        };
        const unsubscribe = transport.listenMessages(responseAction, (receivedId, payload2) => {
          if (receivedId === requestId) {
            cleanup();
            resolve(payload2.value);
          }
        });
        signal?.addEventListener("abort", onAbort, { once: true });
        const requestMessage = enumValue(requestAction, payload);
        transport.postMessage(requestId, requestMessage);
        return promise;
      },
      handleRequest(method, handler) {
        checks();
        const requestAction = composeAction(method, "request");
        const responseAction = composeAction(method, "response");
        return transport.listenMessages(requestAction, (requestId, payload) => {
          handler(payload.value).then((result) => {
            const responseMessage = enumValue(responseAction, result);
            transport.postMessage(requestId, responseMessage);
          }, (error) => {
            provider.logger.error(`handleRequest: handler for "${method}" rejected`, error);
          });
        });
      },
      subscribe(method, payload, callback) {
        checks();
        const events2 = createNanoEvents();
        const startAction = composeAction(method, "start");
        const startPayload = enumValue(startAction, payload);
        const subscriptionKey = getSubscriptionKey(method, startPayload);
        let subscription = activeSubscriptions.get(subscriptionKey);
        function unsubscribeListener() {
          const subscription2 = activeSubscriptions.get(subscriptionKey);
          if (subscription2) {
            const newListeners = subscription2.listeners.filter((listener2) => listener2.call !== callback);
            if (newListeners.length === 0) {
              activeSubscriptions.delete(subscriptionKey);
              subscription2.kill();
            } else {
              subscription2.listeners = newListeners;
            }
          }
        }
        const listener = {
          call: callback,
          unsubscribe: unsubscribeListener
        };
        const publicSubscription = {
          unsubscribe: unsubscribeListener,
          onInterrupt(callback2) {
            return events2.on("interrupt", callback2);
          }
        };
        if (!subscription) {
          const requestId = createRequestId();
          const stopAction = composeAction(method, "stop");
          const interruptAction = composeAction(method, "interrupt");
          const receiveAction = composeAction(method, "receive");
          const unsubscribeReceive = transport.listenMessages(receiveAction, (receivedId, data) => {
            if (receivedId === requestId) {
              const subscription2 = activeSubscriptions.get(subscriptionKey);
              if (subscription2) {
                for (const listener2 of subscription2.listeners) {
                  listener2.call(data.value);
                }
              }
            }
          });
          const unsubscribeInterrupt = transport.listenMessages(interruptAction, (receivedId, data) => {
            if (receivedId === requestId) {
              events2.emit("interrupt", data.value);
              stopSubscription();
            }
          });
          const stopSubscription = () => {
            unsubscribeReceive();
            unsubscribeInterrupt();
            events2.events = {};
          };
          subscription = {
            requestId,
            kill: () => {
              stopSubscription();
              const stopPayload = enumValue(stopAction, void 0);
              transport.postMessage(requestId, stopPayload);
            },
            listeners: [listener]
          };
          activeSubscriptions.set(subscriptionKey, subscription);
          transport.postMessage(requestId, startPayload);
        } else {
          subscription.listeners.push(listener);
        }
        return publicSubscription;
      },
      handleSubscription(method, handler) {
        checks();
        const startAction = composeAction(method, "start");
        const stopAction = composeAction(method, "stop");
        const interruptAction = composeAction(method, "interrupt");
        const receiveAction = composeAction(method, "receive");
        const subscriptions = /* @__PURE__ */ new Map();
        const unsubStart = transport.listenMessages(startAction, (requestId, payload) => {
          if (subscriptions.has(requestId))
            return;
          let interrupted = false;
          const unsubscribe = handler(payload.value, (value) => {
            if (disposed)
              return;
            const receivePayload = enumValue(receiveAction, value);
            transport.postMessage(requestId, receivePayload);
          }, (value) => {
            interrupted = true;
            subscriptions.delete(requestId);
            if (disposed)
              return;
            transport.postMessage(requestId, enumValue(interruptAction, value));
          });
          if (interrupted) {
            unsubscribe();
          } else {
            subscriptions.set(requestId, unsubscribe);
          }
        });
        const unsubStop = transport.listenMessages(stopAction, (requestId) => {
          const unsubscribe = subscriptions.get(requestId);
          if (unsubscribe) {
            subscriptions.delete(requestId);
            unsubscribe();
          }
        });
        const teardown = () => {
          subscriptions.forEach((unsub) => unsub());
          subscriptions.clear();
          unsubStart();
          unsubStop();
          unsubDestroy();
        };
        const unsubDestroy = transport.onDestroy(teardown);
        return teardown;
      },
      postMessage(requestId, payload) {
        checks();
        if (debugListenerCount > 0) {
          events.emit("debugMessage", { direction: "outgoing", requestId, payload });
        }
        messageProvider.postMessage({ requestId, payload });
      },
      listenMessages(action, callback, onError) {
        return messageProvider.subscribe((message) => {
          try {
            if (isEnumVariant(message.payload, action)) {
              callback(message.requestId, message.payload);
            }
          } catch (e) {
            onError?.(e);
          }
        });
      },
      onConnectionStatusChange(callback) {
        callback(connectionStatus);
        return events.on("connectionStatus", callback);
      },
      onDestroy(callback) {
        return events.on("destroy", callback);
      },
      destroy() {
        disposed = true;
        debugProviderUnsubscribe?.();
        debugProviderUnsubscribe = null;
        debugListenerCount = 0;
        provider.dispose();
        changeConnectionStatus("disconnected");
        events.emit("destroy");
        events.events = {};
        handshakeAbortController.abort("Transport disposed");
      },
      onDebugMessage(callback) {
        debugListenerCount++;
        ensureDebugProviderSubscription();
        const safeCallback = (event) => {
          try {
            callback(event);
          } catch (e) {
            console.error("debug listener threw", e);
          }
        };
        const unsubscribe = events.on("debugMessage", safeCallback);
        let disposed2 = false;
        return () => {
          if (disposed2)
            return;
          disposed2 = true;
          unsubscribe();
          debugListenerCount--;
          maybeDisposeDebugProviderSubscription();
        };
      }
    };
    if (provider.isCorrectEnvironment()) {
      transport.handleRequest("host_handshake", async (version) => {
        switch (version.tag) {
          case "v1": {
            codecVersion = version.value;
            switch (version.value) {
              case SCALE_CODEC_PROTOCOL_ID:
                return enumValue(version.tag, resultOk(void 0));
              default:
                return enumValue(version.tag, resultErr(new HandshakeErr.UnsupportedProtocolVersion(void 0)));
            }
          }
          default:
            return enumValue(version.tag, resultErr(new HandshakeErr.UnsupportedProtocolVersion(void 0)));
        }
      });
    }
    return transport;
  }

  // node_modules/@polkadot-api/raw-client/dist/RpcError.js
  var __defProp3 = Object.defineProperty;
  var __defNormalProp3 = (obj, key, value) => key in obj ? __defProp3(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __publicField3 = (obj, key, value) => __defNormalProp3(obj, typeof key !== "symbol" ? key + "" : key, value);
  var RpcError = class extends Error {
    constructor(e) {
      super(e.message);
      __publicField3(this, "code");
      __publicField3(this, "data");
      this.code = e.code;
      this.data = e.data;
      this.name = "RpcError";
    }
  };

  // node_modules/@polkadot-api/json-rpc-provider/dist/index.js
  var isRequest = (msg) => "method" in msg;
  var isResponse = (msg) => !("method" in msg);

  // node_modules/@polkadot-api/raw-client/dist/subscriptions-manager.js
  var getSubscriptionsManager = () => {
    const subscriptions = /* @__PURE__ */ new Map();
    return {
      has: subscriptions.has.bind(subscriptions),
      subscribe(id2, subscriber) {
        subscriptions.set(id2, subscriber);
      },
      unsubscribe(id2) {
        subscriptions.delete(id2);
      },
      next(id2, data) {
        subscriptions.get(id2)?.next(data);
      },
      error(id2, e) {
        const subscriber = subscriptions.get(id2);
        if (subscriber) {
          subscriptions.delete(id2);
          subscriber.error(e);
        }
      },
      errorAll(e) {
        const subscribers2 = [...subscriptions.values()];
        subscriptions.clear();
        subscribers2.forEach((s) => {
          s.error(e);
        });
      }
    };
  };

  // node_modules/@polkadot-api/raw-client/dist/DestroyedError.js
  var DestroyedError = class extends Error {
    constructor() {
      super("Client destroyed");
      this.name = "DestroyedError";
    }
  };

  // node_modules/@polkadot-api/raw-client/dist/createClient.js
  var nextClientId = 1;
  var createClient = (gProvider, onNotification) => {
    let clientId = nextClientId++;
    const responses = /* @__PURE__ */ new Map();
    const subscriptions = getSubscriptionsManager();
    let connection = null;
    const send = (id2, method, params) => {
      connection.send({
        jsonrpc: "2.0",
        id: id2,
        method,
        params
      });
    };
    function onMessage(parsed) {
      if (isResponse(parsed)) {
        const { id: id2 } = parsed;
        const cb = responses.get(id2);
        if (!cb)
          return;
        responses.delete(id2);
        return "error" in parsed ? cb.onError(new RpcError(parsed.error)) : cb.onSuccess(parsed.result, (opaqueId, subscriber) => {
          const subscriptionId = opaqueId;
          subscriptions.subscribe(subscriptionId, subscriber);
          return () => {
            subscriptions.unsubscribe(subscriptionId);
          };
        });
      }
      if (parsed.id === void 0) {
        const { params } = parsed;
        const { subscription: subscriptionId, result, error } = params;
        if (subscriptionId && subscriptions.has(subscriptionId) && ("result" in params || error)) {
          if (error)
            subscriptions.error(subscriptionId, new RpcError(error));
          else
            subscriptions.next(subscriptionId, result);
        } else {
          onNotification?.(parsed);
        }
      } else
        console.warn("Error parsing incomming message: " + JSON.stringify(parsed));
    }
    connection = gProvider(onMessage);
    const disconnect = () => {
      connection?.disconnect();
      connection = null;
      subscriptions.errorAll(new DestroyedError());
      responses.forEach((r) => r.onError(new DestroyedError()));
      responses.clear();
    };
    let nextId = 1;
    const request = (method, params, cb) => {
      if (!connection)
        throw new Error("Not connected");
      const id2 = `${clientId}-${nextId++}`;
      if (cb)
        responses.set(id2, cb);
      send(id2, method, params);
      return () => {
        responses.delete(id2);
      };
    };
    return {
      request,
      disconnect
    };
  };

  // node_modules/@polkadot-api/substrate-client/dist/chainhead/errors.js
  var __defProp4 = Object.defineProperty;
  var __defNormalProp4 = (obj, key, value) => key in obj ? __defProp4(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __publicField4 = (obj, key, value) => __defNormalProp4(obj, key + "", value);
  var _StopError = class _StopError2 extends Error {
    constructor() {
      super("ChainHead stopped");
      this.name = _StopError2.errorName;
    }
  };
  __publicField4(_StopError, "errorName", "StopError");
  var StopError = _StopError;
  var _DisjointError = class _DisjointError2 extends Error {
    constructor() {
      super("ChainHead disjointed");
      this.name = _DisjointError2.errorName;
    }
  };
  __publicField4(_DisjointError, "errorName", "DisjointError");
  var DisjointError = _DisjointError;
  var _OperationLimitError = class _OperationLimitError2 extends Error {
    constructor() {
      super("ChainHead operations limit reached");
      this.name = _OperationLimitError2.errorName;
    }
  };
  __publicField4(_OperationLimitError, "errorName", "OperationLimitError");
  var OperationLimitError = _OperationLimitError;
  var _OperationError = class _OperationError2 extends Error {
    constructor(error) {
      super(error);
      this.name = _OperationError2.errorName;
    }
  };
  __publicField4(_OperationError, "errorName", "OperationError");
  var OperationError = _OperationError;
  var _OperationInaccessibleError = class _OperationInaccessibleError2 extends Error {
    constructor() {
      super("ChainHead operation inaccessible");
      this.name = _OperationInaccessibleError2.errorName;
    }
  };
  __publicField4(_OperationInaccessibleError, "errorName", "OperationInaccessibleError");
  var OperationInaccessibleError = _OperationInaccessibleError;

  // node_modules/@polkadot-api/substrate-client/dist/methods.js
  var chainHead = {
    body: "",
    call: "",
    continue: "",
    follow: "",
    header: "",
    stopOperation: "",
    storage: "",
    unfollow: "",
    unpin: "",
    followEvent: ""
  };
  var chainSpec = {
    chainName: "",
    genesisHash: "",
    properties: ""
  };
  var transaction = {
    broadcast: "",
    stop: ""
  };
  Object.entries({ chainHead, chainSpec, transaction }).forEach(
    ([fnGroupName, methods]) => {
      Object.keys(methods).forEach((methodName) => {
        methods[methodName] = `${fnGroupName}_v1_${methodName}`;
      });
    }
  );

  // node_modules/@polkadot-api/substrate-client/dist/archive/errors.js
  var __defProp5 = Object.defineProperty;
  var __defNormalProp5 = (obj, key, value) => key in obj ? __defProp5(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __publicField5 = (obj, key, value) => __defNormalProp5(obj, key + "", value);
  var _BlockHashNotFoundError = class _BlockHashNotFoundError2 extends Error {
    constructor(hash) {
      super(`Invalid BlockHash: ${hash}`);
      this.name = _BlockHashNotFoundError2.errorName;
    }
  };
  __publicField5(_BlockHashNotFoundError, "errorName", "BlockHashNotFoundError");
  var BlockHashNotFoundError = _BlockHashNotFoundError;
  var _StorageError = class _StorageError2 extends Error {
    constructor(message) {
      super(`Storage Error: ${message}`);
      this.name = _StorageError2.errorName;
    }
  };
  __publicField5(_StorageError, "errorName", "StorageError");
  var StorageError = _StorageError;
  var _CallError = class _CallError2 extends Error {
    constructor(message) {
      super(`Call Error: ${message}`);
      this.name = _CallError2.errorName;
    }
  };
  __publicField5(_CallError, "errorName", "CallError");
  var CallError = _CallError;

  // node_modules/@polkadot-api/substrate-client/dist/internal-utils/noop.js
  var noop3 = () => {
  };

  // node_modules/@polkadot-api/substrate-client/dist/transaction/transaction.js
  var getTransaction = (request) => (tx, error) => {
    let isDone = false;
    let cancel = () => {
      isDone = true;
    };
    request(transaction.broadcast, [tx], {
      onSuccess: (subscriptionId) => {
        if (subscriptionId !== null) {
          cancel = () => {
            request(transaction.stop, [subscriptionId]);
            cancel = noop3;
          };
          if (isDone)
            cancel();
        } else if (!isDone) {
          error(new Error("Max # of broadcasted transactions has been reached"));
        }
      },
      onError: error
    });
    return () => {
      cancel();
    };
  };

  // node_modules/@polkadot-api/substrate-client/dist/internal-utils/deferred-promise.js
  function deferred() {
    let res = () => {
    };
    let rej = () => {
    };
    const promise = new Promise((_res, _rej) => {
      res = _res;
      rej = _rej;
    });
    return { promise, res, rej };
  }

  // node_modules/@polkadot-api/substrate-client/dist/internal-utils/abortablePromiseFn.js
  var abortablePromiseFn = (fn) => (...args) => new Promise((res, rej) => {
    let cancel = noop2;
    const [actualArgs, abortSignal] = args[args.length - 1] instanceof AbortSignal ? [args.slice(0, args.length - 1), args[args.length - 1]] : [args];
    const onAbort = () => {
      cancel();
      rej(new AbortError());
    };
    abortSignal?.addEventListener("abort", onAbort, { once: true });
    const withCleanup = (fn2) => (x) => {
      cancel = noop2;
      abortSignal?.removeEventListener("abort", onAbort);
      fn2(x);
    };
    cancel = fn(...[withCleanup(res), withCleanup(rej), ...actualArgs]);
  });

  // node_modules/@polkadot-api/substrate-client/dist/chainhead/operation-promise.js
  var createOperationPromise = (operationName, factory) => (request) => abortablePromiseFn((res, rej, ...args) => {
    let isRunning = true;
    let cancel = () => {
      isRunning = false;
    };
    const [requestArgs, logicCb] = factory(...args);
    request(operationName, requestArgs, {
      onSuccess: (response, followSubscription) => {
        if (response.result === "limitReached")
          return rej(new OperationLimitError());
        const { operationId } = response;
        const stopOperation = () => {
          request(chainHead.stopOperation, [operationId]);
        };
        if (!isRunning)
          return stopOperation();
        let done = noop3;
        const _res = (x) => {
          isRunning = false;
          done();
          res(x);
        };
        const _rej = (x) => {
          isRunning = false;
          done();
          rej(x);
        };
        done = followSubscription(operationId, {
          next: (e) => {
            const _e = e;
            if (_e.event === "operationError")
              rej(new OperationError(_e.error));
            else if (_e.event === "operationInaccessible")
              rej(new OperationInaccessibleError());
            else
              logicCb(e, _res, _rej);
          },
          error: _rej
        });
        cancel = () => {
          if (isRunning) {
            done();
            stopOperation();
          }
        };
      },
      onError: rej
    });
    return () => {
      cancel();
    };
  });

  // node_modules/@polkadot-api/substrate-client/dist/chainhead/body.js
  var createBodyFn = createOperationPromise(
    chainHead.body,
    (hash) => [
      [hash],
      (e, res) => {
        res(e.value);
      }
    ]
  );

  // node_modules/@polkadot-api/substrate-client/dist/chainhead/call.js
  var createCallFn = createOperationPromise(
    chainHead.call,
    (hash, fnName, callParameters) => [
      [hash, fnName, callParameters],
      (e, res) => {
        res(e.output);
      }
    ]
  );

  // node_modules/@polkadot-api/substrate-client/dist/chainhead/header.js
  var createHeaderFn = (request) => (hash) => new Promise((res, rej) => {
    request(chainHead.header, [hash], {
      onSuccess: res,
      onError: rej
    });
  });

  // node_modules/@polkadot-api/substrate-client/dist/chainhead/storage-subscription.js
  var createStorageCb = (request) => (hash, inputs, childTrie, onItems, onError, onDone, onDiscardedItems) => {
    if (inputs.length === 0) {
      onDone();
      return noop2;
    }
    let isRunning = true;
    let cancel = () => {
      isRunning = false;
    };
    request(chainHead.storage, [hash, inputs, childTrie], {
      onSuccess: (response, followSubscription) => {
        if (response.result === "limitReached" || response.discardedItems === inputs.length)
          return onError(new OperationLimitError());
        const { operationId } = response;
        const stopOperation = () => {
          request(chainHead.stopOperation, [operationId]);
        };
        if (!isRunning)
          return stopOperation();
        const doneListening = followSubscription(response.operationId, {
          next: (event) => {
            switch (event.event) {
              case "operationStorageItems": {
                onItems(event.items);
                break;
              }
              case "operationStorageDone": {
                _onDone();
                break;
              }
              case "operationError": {
                _onError(new OperationError(event.error));
                break;
              }
              case "operationInaccessible": {
                _onError(new OperationInaccessibleError());
                break;
              }
              default:
                request(chainHead.continue, [event.operationId]);
            }
          },
          error: onError
        });
        cancel = () => {
          doneListening();
          request(chainHead.stopOperation, [response.operationId]);
        };
        const _onError = (e) => {
          cancel = noop2;
          doneListening();
          onError(e);
        };
        const _onDone = () => {
          cancel = noop2;
          doneListening();
          onDone();
        };
        onDiscardedItems(response.discardedItems);
      },
      onError
    });
    return () => {
      cancel();
    };
  };

  // node_modules/@polkadot-api/substrate-client/dist/chainhead/storage.js
  var createStorageFn = (request) => {
    const cbStore = createStorageCb(request);
    return abortablePromiseFn((resolve, reject, hash, type, key, childTrie) => {
      const isDescendants = type.startsWith("descendants");
      let result = isDescendants ? [] : null;
      const onItems = isDescendants ? (items) => {
        result.push(items);
      } : (items) => {
        result = items[0]?.[type];
      };
      const cancel = cbStore(
        hash,
        [{ key, type }],
        childTrie ?? null,
        onItems,
        reject,
        () => {
          try {
            resolve(isDescendants ? result.flat() : result);
          } catch (e) {
            reject(e);
          }
        },
        (nDiscarded) => {
          if (nDiscarded > 0) {
            cancel();
            reject(new OperationLimitError());
          }
        }
      );
      return cancel;
    });
  };

  // node_modules/@polkadot-api/substrate-client/dist/chainhead/unpin.js
  var createUnpinFn = (request) => (hashes) => hashes.length > 0 ? new Promise((res, rej) => {
    request(chainHead.unpin, [hashes], {
      onSuccess() {
        res();
      },
      onError: rej
    });
  }) : Promise.resolve();

  // node_modules/@polkadot-api/substrate-client/dist/chainhead/chainhead.js
  function isOperationEvent(event) {
    return event.operationId !== void 0;
  }
  function getChainHead(request) {
    return (withRuntime, onFollowEvent, onFollowError) => {
      const subscriptions = getSubscriptionsManager();
      const ongoingRequests = /* @__PURE__ */ new Set();
      const deferredFollow = deferred();
      let followSubscription = deferredFollow.promise;
      let stopListeningToFollowEvents = noop3;
      const unfollowRequest = (subscriptionId) => {
        request(chainHead.unfollow, [subscriptionId]);
      };
      const stopEverything = (sendUnfollow) => {
        stopListeningToFollowEvents();
        if (followSubscription === null)
          return;
        if (sendUnfollow) {
          if (followSubscription instanceof Promise) {
            followSubscription.then((x) => {
              if (typeof x === "string")
                unfollowRequest(x);
            });
          } else
            unfollowRequest(followSubscription);
        }
        followSubscription = null;
        ongoingRequests.forEach((cb) => {
          cb();
        });
        ongoingRequests.clear();
        subscriptions.errorAll(new DisjointError());
      };
      const onAllFollowEventsNext = (event) => {
        if (isOperationEvent(event))
          return subscriptions.next(event.operationId, event);
        switch (event.event) {
          case "stop":
            onFollowError(new StopError());
            return stopEverything(false);
          case "initialized":
          case "newBlock":
          case "bestBlockChanged":
          case "finalized":
            const { event: type, ...rest } = event;
            return onFollowEvent({ type, ...rest });
        }
      };
      const onAllFollowEventsError = (error) => {
        onFollowError(error);
        stopEverything(!(error instanceof DestroyedError));
      };
      request(chainHead.follow, [withRuntime], {
        onSuccess: (subscriptionId, follow) => {
          if (followSubscription instanceof Promise) {
            followSubscription = subscriptionId;
            stopListeningToFollowEvents = follow(subscriptionId, {
              next: onAllFollowEventsNext,
              error: onAllFollowEventsError
            });
          }
          deferredFollow.res(subscriptionId);
        },
        onError: (e) => {
          followSubscription = null;
          deferredFollow.res(e);
          onFollowError(e);
        }
      });
      const fRequest = (method, params, cb) => {
        const disjoint = () => {
          cb?.onError(new DisjointError());
        };
        if (followSubscription === null) {
          disjoint();
          return noop3;
        }
        const onSubscription = (subscription) => {
          if (!cb)
            return request(method, [subscription, ...params]);
          ongoingRequests.add(disjoint);
          const onSubscribeOperation = (operationId, subscriber) => {
            if (followSubscription === null) {
              subscriber.error(new DisjointError());
              return noop3;
            }
            subscriptions.subscribe(operationId, subscriber);
            return () => {
              subscriptions.unsubscribe(operationId);
            };
          };
          const cleanup = request(method, [subscription, ...params], {
            onSuccess: (response) => {
              ongoingRequests.delete(disjoint);
              cb.onSuccess(response, onSubscribeOperation);
            },
            onError: (e) => {
              ongoingRequests.delete(disjoint);
              cb.onError(e);
            }
          });
          return () => {
            ongoingRequests.delete(disjoint);
            cleanup();
          };
        };
        if (typeof followSubscription === "string")
          return onSubscription(followSubscription);
        let onCancel = noop3;
        followSubscription.then((x) => {
          if (x instanceof Error)
            return disjoint();
          if (followSubscription)
            onCancel = onSubscription(x);
        });
        return () => {
          onCancel();
        };
      };
      return {
        unfollow() {
          stopEverything(true);
        },
        body: createBodyFn(fRequest),
        call: createCallFn(fRequest),
        header: createHeaderFn(fRequest),
        storage: createStorageFn(fRequest),
        storageSubscription: createStorageCb(fRequest),
        unpin: createUnpinFn(fRequest),
        _request: fRequest
      };
    };
  }

  // node_modules/@polkadot-api/substrate-client/dist/chainspec.js
  var createGetChainSpec = (clientRequest) => {
    const request = abortablePromiseFn(
      (onSuccess, onError, method, params) => clientRequest(method, params, { onSuccess, onError })
    );
    let cachedPromise = null;
    return async () => {
      if (cachedPromise)
        return cachedPromise;
      return cachedPromise = Promise.all([
        request(chainSpec.chainName, []),
        request(chainSpec.genesisHash, []),
        request(chainSpec.properties, [])
      ]).then(([name, genesisHash, properties]) => ({
        name,
        genesisHash,
        properties
      }));
    };
  };

  // node_modules/@polkadot-api/substrate-client/dist/archive/storage-subscription.js
  var createStorageCb2 = (archiveRequest) => (hash, inputs, childTrie, onItem, onError, onDone) => {
    if (inputs.length === 0) {
      onDone();
      return noop2;
    }
    let isRunning = true;
    let cancel = () => {
      isRunning = false;
    };
    archiveRequest("storage", [hash, inputs, childTrie], {
      onSuccess: (operationId, followSubscription) => {
        const stopOperation = () => {
          archiveRequest("stopStorage", [operationId]);
        };
        if (!isRunning)
          return stopOperation();
        const doneListening = followSubscription(operationId, {
          next: (event) => {
            const { event: type } = event;
            if (type === "storage") {
              const { event: _, ...item } = event;
              onItem(item);
            } else if (type === "storageDone")
              _onDone();
            else
              _onError(new StorageError(event.error));
          },
          error: onError
        });
        const tearDown = () => {
          cancel = noop2;
          doneListening();
        };
        cancel = () => {
          tearDown();
          stopOperation();
        };
        const _onError = (e) => {
          tearDown();
          onError(e);
        };
        const _onDone = () => {
          tearDown();
          onDone();
        };
      },
      onError
    });
    return () => {
      cancel();
    };
  };

  // node_modules/@polkadot-api/substrate-client/dist/archive/storage.js
  var createStorageFn2 = (cbStore) => abortablePromiseFn((resolve, reject, hash, type, key, childTrie) => {
    const isDescendants = type.startsWith("descendants");
    let result = isDescendants ? [] : null;
    const onItem = isDescendants ? result.push.bind(result) : ({ [type]: res }) => {
      result = res;
    };
    return cbStore(
      hash,
      [{ key, type }],
      childTrie,
      onItem,
      (e) => {
        reject(e);
        result = null;
      },
      () => {
        resolve(result);
        result = null;
      }
    );
  });

  // node_modules/@polkadot-api/substrate-client/dist/archive/archive.js
  var identity = () => (x) => x;
  var handleInvalidBlockHash = () => (result, hash) => {
    if (result === null)
      throw new BlockHashNotFoundError(hash);
    return result;
  };
  var getArchive = (request) => {
    const archiveRequest = (method, ...rest) => request(`archive_v1_${method}`, ...rest);
    const fnCreator = (method) => (mapper) => abortablePromiseFn(
      (res, rej, ...args) => archiveRequest(method, args, {
        onSuccess: (x) => {
          try {
            res(mapper(x, ...args));
          } catch (e) {
            rej(e);
          }
        },
        onError: rej
      })
    );
    const header = fnCreator("header")(
      handleInvalidBlockHash()
    );
    const body = fnCreator("body")(
      handleInvalidBlockHash()
    );
    const storageSubscription = createStorageCb2(archiveRequest);
    const storage = createStorageFn2(storageSubscription);
    const call = fnCreator("call")((x, hash) => {
      if (!x)
        throw new BlockHashNotFoundError(hash);
      if (!x.success)
        throw new CallError(x.error);
      return x.value;
    });
    const finalizedHeight = fnCreator("finalizedHeight")(identity());
    const hashByHeight = fnCreator("hashByHeight")(identity());
    return {
      header,
      body,
      storageSubscription,
      storage,
      call,
      finalizedHeight,
      hashByHeight
    };
  };

  // node_modules/@polkadot-api/substrate-client/dist/substrate-client.js
  var createClient2 = (provider) => {
    const { request, disconnect } = createClient(provider);
    return {
      archive: getArchive(request),
      chainHead: getChainHead(request),
      transaction: getTransaction(request),
      getChainSpecData: createGetChainSpec(request),
      destroy: disconnect,
      request: abortablePromiseFn(
        (onSuccess, onError, method, params) => request(method, params, { onSuccess, onError })
      ),
      _request: request
    };
  };

  // node_modules/@novasamatech/host-container/dist/chainConnectionManager.js
  var TERMINAL_OPERATION_EVENTS = /* @__PURE__ */ new Set([
    "operationBodyDone",
    "operationCallDone",
    "operationStorageDone",
    "operationError",
    "operationInaccessible"
  ]);
  var REFOLLOW_TIMEOUT_MS = 5e3;
  function executeChainHeadOp(response, onEvent, method, params) {
    return new Promise((resolve, reject) => {
      response._request(method, params, {
        onSuccess: (result, onSubscribeOperation) => {
          const operationId = result?.operationId;
          if (operationId) {
            let unsub = () => void 0;
            unsub = onSubscribeOperation(operationId, {
              next: (e) => {
                onEvent(e);
                if (TERMINAL_OPERATION_EVENTS.has(e.event))
                  unsub();
              },
              error: () => unsub()
            });
          }
          resolve(result);
        },
        onError: reject
      });
    });
  }
  function createChainConnectionManager(factory, options = {}) {
    const refollowTimeoutMs = options.refollowTimeoutMs ?? REFOLLOW_TIMEOUT_MS;
    const chains = /* @__PURE__ */ new Map();
    let nextFollowId = 0;
    function teardown(entry) {
      for (const follow of entry.follows.values())
        follow.response?.unfollow();
      entry.follows.clear();
      for (const op of entry.pendingOps) {
        clearTimeout(op.timer);
        op.reject(new Error("Chain disposed"));
      }
      entry.pendingOps = [];
      entry.client.destroy();
    }
    function activeFollow(genesisHash) {
      const entry = chains.get(genesisHash);
      if (!entry)
        return null;
      for (const follow of entry.follows.values()) {
        if (follow.response)
          return follow;
      }
      return null;
    }
    return {
      getOrCreateChain(genesisHash) {
        const existing = chains.get(genesisHash);
        if (existing) {
          existing.refCount++;
          return true;
        }
        const provider = factory(genesisHash);
        if (!provider)
          return false;
        chains.set(genesisHash, {
          client: createClient2(provider),
          follows: /* @__PURE__ */ new Map(),
          pendingOps: [],
          recoveringSince: null,
          refCount: 1
        });
        return true;
      },
      startFollow(genesisHash, withRuntime, onEvent) {
        const entry = chains.get(genesisHash);
        if (!entry)
          throw new Error(`No connection for chain ${genesisHash}`);
        const followId = `f${nextFollowId++}`;
        const follow = { response: null, onEvent };
        entry.follows.set(followId, follow);
        const response = entry.client.chainHead(
          withRuntime,
          // substrate-client renames the spec's `event` field to `type`. Restore it.
          ({ type, ...rest }) => onEvent({ event: type, ...rest }),
          (error) => {
            entry.follows.delete(followId);
            follow.response?.unfollow();
            follow.response = null;
            if (error instanceof StopError) {
              onEvent({ event: "stop" });
              entry.recoveringSince = Date.now();
            }
          }
        );
        follow.response = response;
        entry.recoveringSince = null;
        if (entry.pendingOps.length > 0) {
          const queued = entry.pendingOps;
          entry.pendingOps = [];
          for (const op of queued) {
            clearTimeout(op.timer);
            executeChainHeadOp(response, onEvent, op.method, op.params).then(op.resolve, op.reject);
          }
        }
        return { followId };
      },
      stopFollow(genesisHash, followId) {
        const entry = chains.get(genesisHash);
        if (!entry)
          return;
        const follow = entry.follows.get(followId);
        if (!follow)
          return;
        entry.follows.delete(followId);
        follow.response?.unfollow();
      },
      hasActiveFollow(genesisHash) {
        return activeFollow(genesisHash) !== null;
      },
      chainHeadOp(genesisHash, method, params) {
        const follow = activeFollow(genesisHash);
        if (follow?.response)
          return executeChainHeadOp(follow.response, follow.onEvent, method, params);
        const entry = chains.get(genesisHash);
        if (!entry || entry.recoveringSince === null) {
          return Promise.reject(new Error("No active follow for this chain"));
        }
        if (Date.now() - entry.recoveringSince > refollowTimeoutMs) {
          entry.recoveringSince = null;
          return Promise.reject(new Error("No active follow for this chain"));
        }
        return new Promise((resolve, reject) => {
          const op = {
            method,
            params,
            resolve,
            reject,
            timer: setTimeout(() => {
              const idx = entry.pendingOps.indexOf(op);
              if (idx !== -1)
                entry.pendingOps.splice(idx, 1);
              reject(new Error("No active follow for this chain"));
            }, refollowTimeoutMs)
          };
          entry.pendingOps.push(op);
        });
      },
      sendRequest(genesisHash, method, params) {
        const entry = chains.get(genesisHash);
        if (!entry)
          return Promise.reject(new Error(`No connection for chain ${genesisHash}`));
        return entry.client.request(method, params);
      },
      releaseChain(genesisHash) {
        const entry = chains.get(genesisHash);
        if (!entry)
          return;
        if (--entry.refCount <= 0) {
          teardown(entry);
          chains.delete(genesisHash);
        }
      },
      dispose() {
        for (const entry of chains.values())
          teardown(entry);
        chains.clear();
      },
      convertJsonRpcEventToTyped,
      convertOperationStartedResult,
      convertStorageQueryTypeToJsonRpc
    };
  }
  function convertRuntime(runtime) {
    if (!runtime || typeof runtime !== "object")
      return void 0;
    const rt = runtime;
    if (rt.type === "valid") {
      const spec = rt.spec;
      const apis = spec.apis;
      return enumValue("Valid", {
        specName: spec.specName,
        implName: spec.implName,
        specVersion: spec.specVersion,
        implVersion: spec.implVersion,
        transactionVersion: spec.transactionVersion,
        apis: apis ? Object.entries(apis).map(([name, version]) => [name, version]) : []
      });
    }
    if (rt.type === "invalid")
      return enumValue("Invalid", { error: rt.error });
    return void 0;
  }
  function convertJsonRpcEventToTyped(event) {
    switch (event.event) {
      case "initialized":
        return enumValue("Initialized", {
          finalizedBlockHashes: event.finalizedBlockHashes,
          finalizedBlockRuntime: convertRuntime(event.finalizedBlockRuntime)
        });
      case "newBlock":
        return enumValue("NewBlock", {
          blockHash: event.blockHash,
          parentBlockHash: event.parentBlockHash,
          newRuntime: convertRuntime(event.newRuntime)
        });
      case "bestBlockChanged":
        return enumValue("BestBlockChanged", { bestBlockHash: event.bestBlockHash });
      case "finalized":
        return enumValue("Finalized", {
          finalizedBlockHashes: event.finalizedBlockHashes,
          prunedBlockHashes: event.prunedBlockHashes
        });
      case "operationBodyDone":
        return enumValue("OperationBodyDone", {
          operationId: event.operationId,
          value: event.value
        });
      case "operationCallDone":
        return enumValue("OperationCallDone", {
          operationId: event.operationId,
          output: event.output
        });
      case "operationStorageItems":
        return enumValue("OperationStorageItems", {
          operationId: event.operationId,
          items: event.items.map((item) => ({
            key: item.key,
            value: item.value ?? null,
            hash: item.hash ?? null,
            closestDescendantMerkleValue: item.closestDescendantMerkleValue ?? null
          }))
        });
      case "operationStorageDone":
        return enumValue("OperationStorageDone", { operationId: event.operationId });
      case "operationWaitingForContinue":
        return enumValue("OperationWaitingForContinue", { operationId: event.operationId });
      case "operationInaccessible":
        return enumValue("OperationInaccessible", { operationId: event.operationId });
      case "operationError":
        return enumValue("OperationError", {
          operationId: event.operationId,
          error: event.error
        });
      case "stop":
      default:
        return enumValue("Stop", void 0);
    }
  }
  function convertOperationStartedResult(result) {
    const r = result;
    return r?.result === "started" ? enumValue("Started", { operationId: r.operationId }) : enumValue("LimitReached", void 0);
  }
  function convertStorageQueryTypeToJsonRpc(type) {
    return type.charAt(0).toLowerCase() + type.slice(1);
  }

  // node_modules/@novasamatech/host-container/dist/debugBus.js
  var bus = createNanoEvents();
  var sources = /* @__PURE__ */ new Set();
  var activeSources = /* @__PURE__ */ new Map();
  var subscriberCount = 0;
  function activateSource(source) {
    if (activeSources.has(source))
      return;
    activeSources.set(source, source());
  }
  function deactivateSource(source) {
    const unsubscribe = activeSources.get(source);
    if (!unsubscribe)
      return;
    activeSources.delete(source);
    unsubscribe();
  }
  function emitHostApiDebugMessage(event) {
    bus.emit("message", event);
  }
  function registerHostApiDebugSource(source) {
    sources.add(source);
    if (subscriberCount > 0)
      activateSource(source);
    let disposed = false;
    return () => {
      if (disposed)
        return;
      disposed = true;
      sources.delete(source);
      deactivateSource(source);
    };
  }

  // node_modules/@novasamatech/host-container/dist/createContainer.js
  var UNSUPPORTED_MESSAGE_FORMAT_ERROR = "Unsupported message format";
  var NOT_IMPLEMENTED = "Not implemented";
  function guardVersion(value, tag, error) {
    if (!value) {
      return err(error);
    }
    if (isEnumVariant(value, tag)) {
      return ok(value.value);
    }
    return err(error);
  }
  function createContainer(provider, options = {}) {
    const transport = createTransport(provider);
    if (!transport.isCorrectEnvironment()) {
      throw new Error("Transport is not available: dapp provider has incorrect environment");
    }
    const { productId } = options;
    const unregisterGlobalDebugSource = registerHostApiDebugSource(() => transport.onDebugMessage(({ direction, requestId, payload }) => {
      emitHostApiDebugMessage({ direction, productId, requestId, payload });
    }));
    transport.onDestroy(unregisterGlobalDebugSource);
    function init() {
      transport.isReady();
    }
    function makeRequestSlot(method, defaultHandler) {
      let current = defaultHandler;
      let version = 0;
      transport.handleRequest(method, (params) => current(params));
      return {
        update: (handler) => {
          current = handler;
          const myVersion = ++version;
          return () => {
            if (myVersion !== version)
              return;
            version++;
            current = defaultHandler;
          };
        },
        call: (...args) => current(...args)
      };
    }
    function makeSubscriptionSlot(method, defaultHandler) {
      let current = defaultHandler;
      let version = 0;
      transport.handleSubscription(method, (params, send, interrupt) => current(params, send, interrupt));
      return (handler) => {
        current = handler;
        const myVersion = ++version;
        return () => {
          if (myVersion !== version)
            return;
          version++;
          current = defaultHandler;
        };
      };
    }
    function makeNotImplementedSlot(method, makeError) {
      const handler = async () => enumValue("v1", resultErr(makeError()));
      return makeRequestSlot(method, handler);
    }
    function makeInterruptSlot(method, makeDefaultInterrupt) {
      const defaultHandler = (_params, _send, interrupt) => {
        queueMicrotask(() => interrupt(makeDefaultInterrupt()));
        return () => {
        };
      };
      const update = makeSubscriptionSlot(method, defaultHandler);
      return { update, makeDefaultInterrupt };
    }
    function makePermissionGatedRequestSlot(method, permissionVariant, makeError) {
      const defaultHandler = async () => enumValue("v1", resultErr(makeError()));
      let current = defaultHandler;
      let version = 0;
      transport.handleRequest(method, async (params) => {
        const permissionResponse = await handleRemotePermissionSlot.call(enumValue("v1", enumValue(permissionVariant, void 0)));
        const permissionGranted = isEnumVariant(permissionResponse, "v1") && permissionResponse.value.success === true && permissionResponse.value.value === true;
        if (!permissionGranted) {
          return enumValue("v1", resultErr(makeError()));
        }
        return current(params);
      });
      return {
        update: (handler) => {
          current = handler;
          const myVersion = ++version;
          return () => {
            if (myVersion !== version)
              return;
            version++;
            current = defaultHandler;
          };
        },
        call: (...args) => current(...args)
      };
    }
    function makeDevicePermissionGatedRequestSlot(method, permissionVariant, makeError) {
      const defaultHandler = async () => enumValue("v1", resultErr(makeError()));
      let current = defaultHandler;
      let version = 0;
      transport.handleRequest(method, async (params) => {
        const permissionResponse = await handleDevicePermissionSlot.call(enumValue("v1", permissionVariant));
        const permissionGranted = isEnumVariant(permissionResponse, "v1") && permissionResponse.value.success === true && permissionResponse.value.value === true;
        if (!permissionGranted) {
          return enumValue("v1", resultErr(makeError()));
        }
        return current(params);
      });
      return {
        update: (handler) => {
          current = handler;
          const myVersion = ++version;
          return () => {
            if (myVersion !== version)
              return;
            version++;
            current = defaultHandler;
          };
        },
        call: (...args) => current(...args)
      };
    }
    function handleV1Request(slot, makeError, handler) {
      init();
      const version = "v1";
      return slot.update(async (params) => {
        const error = makeError();
        return guardVersion(params, version, error).asyncMap(async (p) => await handler(p, { ok: okAsync, err: errAsync })).andThen((r) => r.map((v) => enumValue(version, resultOk(v)))).orElse((r) => ok(enumValue(version, resultErr(r)))).unwrapOr(enumValue(version, resultErr(error)));
      });
    }
    function handleV1Subscription(slot, handler) {
      init();
      const version = "v1";
      const slotHandler = (params, send, interrupt) => {
        return guardVersion(params, version, null).map((p) => handler(p, (payload) => send(enumValue(version, payload)), (payload) => interrupt(enumValue(version, payload)))).orTee(() => interrupt(slot.makeDefaultInterrupt())).unwrapOr(() => {
        });
      };
      return slot.update(slotHandler);
    }
    const handleGetUserIdSlot = makeNotImplementedSlot("host_get_user_id", () => new GetUserIdErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleRequestLoginSlot = makeNotImplementedSlot("host_request_login", () => new LoginErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleAccountGetSlot = makeNotImplementedSlot("host_account_get", () => new RequestCredentialsErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleAccountGetAliasSlot = makeNotImplementedSlot("host_account_get_alias", () => new RequestCredentialsErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleGetLegacyAccountsSlot = makeNotImplementedSlot("host_get_legacy_accounts", () => new RequestCredentialsErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleAccountCreateProofSlot = makeNotImplementedSlot("host_account_create_proof", () => new CreateProofErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleDeriveEntropySlot = makeNotImplementedSlot("host_derive_entropy", () => new DeriveEntropyErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleLocalStorageReadSlot = makeNotImplementedSlot("host_local_storage_read", () => new StorageErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleLocalStorageWriteSlot = makeNotImplementedSlot("host_local_storage_write", () => new StorageErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleLocalStorageClearSlot = makeNotImplementedSlot("host_local_storage_clear", () => new StorageErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleSignRawSlot = makeNotImplementedSlot("host_sign_raw", () => new SigningErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleSignPayloadSlot = makeNotImplementedSlot("host_sign_payload", () => new SigningErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleSignRawWithLegacyAccountSlot = makeNotImplementedSlot("host_sign_raw_with_legacy_account", () => new SigningErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleSignPayloadWithLegacyAccountSlot = makeNotImplementedSlot("host_sign_payload_with_legacy_account", () => new SigningErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleCreateTransactionSlot = makeNotImplementedSlot("host_create_transaction", () => new CreateTransactionErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleCreateTransactionWithLegacyAccountSlot = makeNotImplementedSlot("host_create_transaction_with_legacy_account", () => new CreateTransactionErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleFeatureSupportedSlot = makeNotImplementedSlot("host_feature_supported", () => new GenericError({ reason: NOT_IMPLEMENTED }));
    const handleDevicePermissionSlot = makeNotImplementedSlot("host_device_permission", () => new GenericError({ reason: NOT_IMPLEMENTED }));
    const handleRemotePermissionSlot = makeNotImplementedSlot("remote_permission", () => new GenericError({ reason: NOT_IMPLEMENTED }));
    const handlePushNotificationSlot = makeDevicePermissionGatedRequestSlot("host_push_notification", "Notifications", () => new PushNotificationError2.Unknown({ reason: NOT_IMPLEMENTED }));
    const handlePushNotificationCancelSlot = makeDevicePermissionGatedRequestSlot("host_push_notification_cancel", "Notifications", () => new GenericError({ reason: NOT_IMPLEMENTED }));
    const handleNavigateToSlot = makeNotImplementedSlot("host_navigate_to", () => new NavigateToErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleChatCreateRoomSlot = makeNotImplementedSlot("host_chat_create_room", () => new ChatRoomRegistrationErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleChatBotRegistrationSlot = makeNotImplementedSlot("host_chat_register_bot", () => new ChatBotRegistrationErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleChatPostMessageSlot = makeNotImplementedSlot("host_chat_post_message", () => new ChatMessagePostingErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleStatementStoreSubmitSlot = makePermissionGatedRequestSlot("remote_statement_store_submit", "StatementSubmit", () => new GenericError({ reason: NOT_IMPLEMENTED }));
    const handleStatementStoreCreateProofSlot = makeNotImplementedSlot("remote_statement_store_create_proof", () => new StatementProofErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleStatementStoreCreateProofAuthorizedSlot = makeNotImplementedSlot("remote_statement_store_create_proof_authorized", () => new StatementProofErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handlePreimageSubmitSlot = makePermissionGatedRequestSlot("remote_preimage_submit", "PreimageSubmit", () => new PreimageSubmitErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handlePaymentTopUpSlot = makeNotImplementedSlot("host_payment_top_up", () => new PaymentTopUpErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handlePaymentRequestSlot = makeNotImplementedSlot("host_payment_request", () => new PaymentRequestErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleRequestResourceAllocationSlot = makeNotImplementedSlot("host_request_resource_allocation", () => new ResourceAllocationErr.Unknown({ reason: NOT_IMPLEMENTED }));
    const handleThemeSubscribeSlot = makeInterruptSlot("host_theme_subscribe", () => enumValue("v1", void 0));
    const handleAccountConnectionStatusSubscribeSlot = makeInterruptSlot("host_account_connection_status_subscribe", () => enumValue("v1", void 0));
    const handleChatListSubscribeSlot = makeInterruptSlot("host_chat_list_subscribe", () => enumValue("v1", void 0));
    const handleChatActionSubscribeSlot = makeInterruptSlot("host_chat_action_subscribe", () => enumValue("v1", void 0));
    const handleStatementStoreSubscribeSlot = makeInterruptSlot("remote_statement_store_subscribe", () => enumValue("v1", void 0));
    const handlePreimageLookupSubscribeSlot = makeInterruptSlot("remote_preimage_lookup_subscribe", () => enumValue("v1", void 0));
    const handlePaymentBalanceSubscribeSlot = makeInterruptSlot("host_payment_balance_subscribe", () => enumValue("v1", new PaymentBalanceErr.Unknown({ reason: NOT_IMPLEMENTED })));
    const handlePaymentStatusSubscribeSlot = makeInterruptSlot("host_payment_status_subscribe", () => enumValue("v1", new PaymentStatusErr.Unknown({ reason: NOT_IMPLEMENTED })));
    return {
      handleFeatureSupported(handler) {
        return handleV1Request(handleFeatureSupportedSlot, () => new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleDevicePermission(handler) {
        return handleV1Request(handleDevicePermissionSlot, () => new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handlePermission(handler) {
        return handleV1Request(handleRemotePermissionSlot, () => new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handlePushNotification(handler) {
        return handleV1Request(handlePushNotificationSlot, () => new PushNotificationError2.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handlePushNotificationCancel(handler) {
        return handleV1Request(handlePushNotificationCancelSlot, () => new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleNavigateTo(handler) {
        return handleV1Request(handleNavigateToSlot, () => new NavigateToErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleDeriveEntropy(handler) {
        return handleV1Request(handleDeriveEntropySlot, () => new DeriveEntropyErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleLocalStorageRead(handler) {
        return handleV1Request(handleLocalStorageReadSlot, () => new StorageErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleLocalStorageWrite(handler) {
        return handleV1Request(handleLocalStorageWriteSlot, () => new StorageErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleLocalStorageClear(handler) {
        return handleV1Request(handleLocalStorageClearSlot, () => new StorageErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleThemeSubscribe(handler) {
        return handleV1Subscription(handleThemeSubscribeSlot, handler);
      },
      handleGetUserId(handler) {
        return handleV1Request(handleGetUserIdSlot, () => new GetUserIdErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleRequestLogin(handler) {
        return handleV1Request(handleRequestLoginSlot, () => new LoginErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleAccountConnectionStatusSubscribe(handler) {
        return handleV1Subscription(handleAccountConnectionStatusSubscribeSlot, handler);
      },
      handleAccountGet(handler) {
        return handleV1Request(handleAccountGetSlot, () => new RequestCredentialsErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleAccountGetAlias(handler) {
        return handleV1Request(handleAccountGetAliasSlot, () => new RequestCredentialsErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleAccountCreateProof(handler) {
        return handleV1Request(handleAccountCreateProofSlot, () => new CreateProofErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleGetLegacyAccounts(handler) {
        return handleV1Request(handleGetLegacyAccountsSlot, () => new RequestCredentialsErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleCreateTransaction(handler) {
        return handleV1Request(handleCreateTransactionSlot, () => new CreateTransactionErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleCreateTransactionWithLegacyAccount(handler) {
        return handleV1Request(handleCreateTransactionWithLegacyAccountSlot, () => new CreateTransactionErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleSignRaw(handler) {
        return handleV1Request(handleSignRawSlot, () => new SigningErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleSignPayload(handler) {
        return handleV1Request(handleSignPayloadSlot, () => new SigningErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleSignRawWithLegacyAccount(handler) {
        return handleV1Request(handleSignRawWithLegacyAccountSlot, () => new SigningErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleSignPayloadWithLegacyAccount(handler) {
        return handleV1Request(handleSignPayloadWithLegacyAccountSlot, () => new SigningErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleChatCreateRoom(handler) {
        return handleV1Request(handleChatCreateRoomSlot, () => new ChatRoomRegistrationErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleChatBotRegistration(handler) {
        return handleV1Request(handleChatBotRegistrationSlot, () => new ChatBotRegistrationErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleChatListSubscribe(handler) {
        return handleV1Subscription(handleChatListSubscribeSlot, handler);
      },
      handleChatPostMessage(handler) {
        return handleV1Request(handleChatPostMessageSlot, () => new ChatMessagePostingErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleChatActionSubscribe(handler) {
        return handleV1Subscription(handleChatActionSubscribeSlot, handler);
      },
      renderChatCustomMessage({ messageId, messageType, payload }, callback) {
        init();
        return transport.subscribe("product_chat_custom_message_render_subscribe", enumValue("v1", { messageId, messageType, payload }), (value) => {
          if (value.tag === "v1") {
            callback(value.value);
          }
        });
      },
      handleStatementStoreSubscribe(handler) {
        return handleV1Subscription(handleStatementStoreSubscribeSlot, handler);
      },
      handleStatementStoreCreateProof(handler) {
        return handleV1Request(handleStatementStoreCreateProofSlot, () => new StatementProofErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleStatementStoreCreateProofAuthorized(handler) {
        return handleV1Request(handleStatementStoreCreateProofAuthorizedSlot, () => new StatementProofErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handleStatementStoreSubmit(handler) {
        return handleV1Request(handleStatementStoreSubmitSlot, () => new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handlePreimageLookupSubscribe(handler) {
        return handleV1Subscription(handlePreimageLookupSubscribeSlot, handler);
      },
      handlePreimageSubmit(handler) {
        return handleV1Request(handlePreimageSubmitSlot, () => new PreimageSubmitErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handlePaymentBalanceSubscribe(handler) {
        return handleV1Subscription(handlePaymentBalanceSubscribeSlot, handler);
      },
      handlePaymentTopUp(handler) {
        return handleV1Request(handlePaymentTopUpSlot, () => new PaymentTopUpErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handlePaymentRequest(handler) {
        return handleV1Request(handlePaymentRequestSlot, () => new PaymentRequestErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      handlePaymentStatusSubscribe(handler) {
        return handleV1Subscription(handlePaymentStatusSubscribeSlot, handler);
      },
      handleRequestResourceAllocation(handler) {
        return handleV1Request(handleRequestResourceAllocationSlot, () => new ResourceAllocationErr.Unknown({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR }), handler);
      },
      // chain interaction
      handleChainConnection(factory) {
        init();
        const manager = createChainConnectionManager(factory);
        const cleanups = [];
        cleanups.push(transport.handleSubscription("remote_chain_head_follow_subscribe", (params, send, interrupt) => {
          if (!isEnumVariant(params, "v1")) {
            interrupt(enumValue("v1", void 0));
            return () => {
            };
          }
          const { genesisHash, withRuntime } = params.value;
          const entry = manager.getOrCreateChain(genesisHash);
          if (!entry) {
            interrupt(enumValue("v1", void 0));
            return () => {
            };
          }
          const { followId } = manager.startFollow(genesisHash, withRuntime, (event) => {
            const typedEvent = manager.convertJsonRpcEventToTyped(event);
            send(enumValue("v1", typedEvent));
          });
          return () => {
            manager.stopFollow(genesisHash, followId);
            manager.releaseChain(genesisHash);
          };
        }));
        cleanups.push(transport.handleRequest("remote_chain_head_header", async (message) => {
          if (!isEnumVariant(message, "v1")) {
            return enumValue("v1", resultErr(new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR })));
          }
          const { genesisHash, hash } = message.value;
          if (!manager.hasActiveFollow(genesisHash)) {
            return enumValue("v1", resultErr(new GenericError({ reason: "No active follow for this chain" })));
          }
          try {
            const result = await manager.chainHeadOp(genesisHash, "chainHead_v1_header", [hash]);
            return enumValue("v1", resultOk(result));
          } catch (e) {
            return enumValue("v1", resultErr(new GenericError({ reason: String(e) })));
          }
        }));
        cleanups.push(transport.handleRequest("remote_chain_head_body", async (message) => {
          if (!isEnumVariant(message, "v1")) {
            return enumValue("v1", resultErr(new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR })));
          }
          const { genesisHash, hash } = message.value;
          if (!manager.hasActiveFollow(genesisHash)) {
            return enumValue("v1", resultErr(new GenericError({ reason: "No active follow for this chain" })));
          }
          try {
            const result = await manager.chainHeadOp(genesisHash, "chainHead_v1_body", [hash]);
            return enumValue("v1", resultOk(manager.convertOperationStartedResult(result)));
          } catch (e) {
            return enumValue("v1", resultErr(new GenericError({ reason: String(e) })));
          }
        }));
        cleanups.push(transport.handleRequest("remote_chain_head_storage", async (message) => {
          if (!isEnumVariant(message, "v1")) {
            return enumValue("v1", resultErr(new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR })));
          }
          const { genesisHash, hash, items, childTrie } = message.value;
          if (!manager.hasActiveFollow(genesisHash)) {
            return enumValue("v1", resultErr(new GenericError({ reason: "No active follow for this chain" })));
          }
          const jsonRpcItems = items.map((item) => ({
            key: item.key,
            type: manager.convertStorageQueryTypeToJsonRpc(item.queryType)
          }));
          try {
            const result = await manager.chainHeadOp(genesisHash, "chainHead_v1_storage", [
              hash,
              jsonRpcItems,
              childTrie
            ]);
            return enumValue("v1", resultOk(manager.convertOperationStartedResult(result)));
          } catch (e) {
            return enumValue("v1", resultErr(new GenericError({ reason: String(e) })));
          }
        }));
        cleanups.push(transport.handleRequest("remote_chain_head_call", async (message) => {
          if (!isEnumVariant(message, "v1")) {
            return enumValue("v1", resultErr(new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR })));
          }
          const params = message.value;
          if (!manager.hasActiveFollow(params.genesisHash)) {
            return enumValue("v1", resultErr(new GenericError({ reason: "No active follow for this chain" })));
          }
          try {
            const result = await manager.chainHeadOp(params.genesisHash, "chainHead_v1_call", [
              params.hash,
              params.function,
              params.callParameters
            ]);
            return enumValue("v1", resultOk(manager.convertOperationStartedResult(result)));
          } catch (e) {
            return enumValue("v1", resultErr(new GenericError({ reason: String(e) })));
          }
        }));
        cleanups.push(transport.handleRequest("remote_chain_head_unpin", async (message) => {
          if (!isEnumVariant(message, "v1")) {
            return enumValue("v1", resultErr(new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR })));
          }
          const { genesisHash, hashes } = message.value;
          if (!manager.hasActiveFollow(genesisHash)) {
            return enumValue("v1", resultErr(new GenericError({ reason: "No active follow for this chain" })));
          }
          try {
            await manager.chainHeadOp(genesisHash, "chainHead_v1_unpin", [hashes]);
            return enumValue("v1", resultOk(void 0));
          } catch (e) {
            return enumValue("v1", resultErr(new GenericError({ reason: String(e) })));
          }
        }));
        cleanups.push(transport.handleRequest("remote_chain_head_continue", async (message) => {
          if (!isEnumVariant(message, "v1")) {
            return enumValue("v1", resultErr(new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR })));
          }
          const { genesisHash, operationId } = message.value;
          if (!manager.hasActiveFollow(genesisHash)) {
            return enumValue("v1", resultErr(new GenericError({ reason: "No active follow for this chain" })));
          }
          try {
            await manager.chainHeadOp(genesisHash, "chainHead_v1_continue", [operationId]);
            return enumValue("v1", resultOk(void 0));
          } catch (e) {
            return enumValue("v1", resultErr(new GenericError({ reason: String(e) })));
          }
        }));
        cleanups.push(transport.handleRequest("remote_chain_head_stop_operation", async (message) => {
          if (!isEnumVariant(message, "v1")) {
            return enumValue("v1", resultErr(new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR })));
          }
          const { genesisHash, operationId } = message.value;
          if (!manager.hasActiveFollow(genesisHash)) {
            return enumValue("v1", resultErr(new GenericError({ reason: "No active follow for this chain" })));
          }
          try {
            await manager.chainHeadOp(genesisHash, "chainHead_v1_stopOperation", [operationId]);
            return enumValue("v1", resultOk(void 0));
          } catch (e) {
            return enumValue("v1", resultErr(new GenericError({ reason: String(e) })));
          }
        }));
        cleanups.push(transport.handleRequest("remote_chain_spec_genesis_hash", async (message) => {
          if (!isEnumVariant(message, "v1")) {
            return enumValue("v1", resultErr(new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR })));
          }
          const genesisHash = message.value;
          const entry = manager.getOrCreateChain(genesisHash);
          if (!entry) {
            return enumValue("v1", resultErr(new GenericError({ reason: "Chain not supported" })));
          }
          try {
            const result = await manager.sendRequest(genesisHash, "chainSpec_v1_genesisHash", []);
            manager.releaseChain(genesisHash);
            return enumValue("v1", resultOk(result));
          } catch (e) {
            manager.releaseChain(genesisHash);
            return enumValue("v1", resultErr(new GenericError({ reason: String(e) })));
          }
        }));
        cleanups.push(transport.handleRequest("remote_chain_spec_chain_name", async (message) => {
          if (!isEnumVariant(message, "v1")) {
            return enumValue("v1", resultErr(new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR })));
          }
          const genesisHash = message.value;
          const entry = manager.getOrCreateChain(genesisHash);
          if (!entry) {
            return enumValue("v1", resultErr(new GenericError({ reason: "Chain not supported" })));
          }
          try {
            const result = await manager.sendRequest(genesisHash, "chainSpec_v1_chainName", []);
            manager.releaseChain(genesisHash);
            return enumValue("v1", resultOk(result));
          } catch (e) {
            manager.releaseChain(genesisHash);
            return enumValue("v1", resultErr(new GenericError({ reason: String(e) })));
          }
        }));
        cleanups.push(transport.handleRequest("remote_chain_spec_properties", async (message) => {
          if (!isEnumVariant(message, "v1")) {
            return enumValue("v1", resultErr(new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR })));
          }
          const genesisHash = message.value;
          const entry = manager.getOrCreateChain(genesisHash);
          if (!entry) {
            return enumValue("v1", resultErr(new GenericError({ reason: "Chain not supported" })));
          }
          try {
            const result = await manager.sendRequest(genesisHash, "chainSpec_v1_properties", []);
            manager.releaseChain(genesisHash);
            return enumValue("v1", resultOk(typeof result === "string" ? result : JSON.stringify(result)));
          } catch (e) {
            manager.releaseChain(genesisHash);
            return enumValue("v1", resultErr(new GenericError({ reason: String(e) })));
          }
        }));
        cleanups.push(transport.handleRequest("remote_chain_transaction_broadcast", async (message) => {
          if (!isEnumVariant(message, "v1")) {
            return enumValue("v1", resultErr(new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR })));
          }
          const { genesisHash, transaction: transaction2 } = message.value;
          const permissionResponse = await handleRemotePermissionSlot.call(enumValue("v1", enumValue("ChainSubmit", void 0)));
          const permissionGranted = isEnumVariant(permissionResponse, "v1") && permissionResponse.value.success === true && permissionResponse.value.value === true;
          if (!permissionGranted) {
            return enumValue("v1", resultErr(new GenericError({ reason: "Permission denied" })));
          }
          const entry = manager.getOrCreateChain(genesisHash);
          if (!entry) {
            return enumValue("v1", resultErr(new GenericError({ reason: "Chain not supported" })));
          }
          try {
            const result = await manager.sendRequest(genesisHash, "transaction_v1_broadcast", [transaction2]);
            return enumValue("v1", resultOk(result ?? null));
          } catch (e) {
            return enumValue("v1", resultErr(new GenericError({ reason: String(e) })));
          } finally {
            manager.releaseChain(genesisHash);
          }
        }));
        cleanups.push(transport.handleRequest("remote_chain_transaction_stop", async (message) => {
          if (!isEnumVariant(message, "v1")) {
            return enumValue("v1", resultErr(new GenericError({ reason: UNSUPPORTED_MESSAGE_FORMAT_ERROR })));
          }
          const { genesisHash, operationId } = message.value;
          const entry = manager.getOrCreateChain(genesisHash);
          if (!entry) {
            return enumValue("v1", resultErr(new GenericError({ reason: "Chain not supported" })));
          }
          try {
            await manager.sendRequest(genesisHash, "transaction_v1_stop", [operationId]);
            manager.releaseChain(genesisHash);
            return enumValue("v1", resultOk(void 0));
          } catch (e) {
            manager.releaseChain(genesisHash);
            return enumValue("v1", resultErr(new GenericError({ reason: String(e) })));
          }
        }));
        let disposed = false;
        const dispose = () => {
          if (disposed)
            return;
          disposed = true;
          unsubscribeDestroy();
          for (const fn of cleanups)
            fn();
          manager.dispose();
        };
        const unsubscribeDestroy = transport.onDestroy(dispose);
        return dispose;
      },
      isReady() {
        return transport.isReady();
      },
      subscribeProductConnectionStatus(callback) {
        const unsubscribe = transport.onConnectionStatusChange(callback);
        init();
        return unsubscribe;
      },
      dispose() {
        transport.destroy();
      },
      onDebugMessage(callback) {
        return transport.onDebugMessage(({ direction, requestId, payload }) => {
          callback({ direction, productId, requestId, payload });
        });
      }
    };
  }

  // src/native-transport.ts
  function createNativeTransport(sendToNative) {
    const pending = /* @__PURE__ */ new Map();
    let nextId = 0;
    window["__container_callback__"] = (id2, payload) => {
      const entry = pending.get(id2);
      if (!entry)
        return;
      const msg = typeof payload === "string" ? JSON.parse(payload) : payload;
      if ("value" in msg) {
        entry.resolve?.(msg.value);
        pending.delete(id2);
      } else if ("error" in msg) {
        const e = new Error(msg.error);
        entry.reject?.(e);
        entry.onError?.(e);
        pending.delete(id2);
      } else if ("update" in msg) {
        entry.onUpdate?.(msg.update);
      } else if ("complete" in msg) {
        pending.delete(id2);
      }
    };
    return {
      callNative(method, params) {
        return new Promise((resolve, reject) => {
          const id2 = `r${nextId++}`;
          pending.set(id2, { resolve, reject });
          sendToNative({ type: "request", id: id2, method, params });
        });
      },
      subscribeNative(method, params, onUpdate, onError) {
        const id2 = `r${nextId++}`;
        pending.set(id2, { onUpdate, onError });
        sendToNative({ type: "subscribe", id: id2, method, params });
        return () => {
          pending.delete(id2);
          sendToNative({ type: "unsubscribe", id: id2 });
        };
      }
    };
  }

  // node_modules/@polkadot-api/json-rpc-provider-proxy/dist/get-opaque-token.js
  var count = 0;
  var getOpaqueToken = () => `proxyOpaque${count++}`;

  // node_modules/@polkadot-api/json-rpc-provider-proxy/dist/json-rpc-message.js
  var jsonRpcReq = (msg) => ({
    jsonrpc: "2.0",
    ...msg
  });
  var jsonRpcRsp = (msg) => ({
    jsonrpc: "2.0",
    ...msg
  });

  // node_modules/@polkadot-api/json-rpc-provider-proxy/dist/get-proxy.js
  var getInternalId = () => `___proxyInternalId__${getOpaqueToken()}`;
  var getProxy = (toConsumer) => {
    let state = {
      type: 1,
      activeBroadcasts: /* @__PURE__ */ new Map(),
      pending: []
    };
    const onMsgFromProvider = (parsed) => {
      let isActive = true;
      if (state.type === 0) {
        if (isResponse(parsed)) {
          const { id: id2 } = parsed;
          const synToken = state.pendingBroadcasts.get(id2);
          if (synToken) {
            state.pendingBroadcasts.delete(id2);
            if (!("result" in parsed))
              return;
            const upToken = parsed.result;
            const activeBroadcast = state.activeBroadcasts.get(synToken);
            if (activeBroadcast)
              activeBroadcast.upToken = upToken;
            else
              state.connection.send(
                jsonRpcReq({
                  id: getInternalId(),
                  method: "transaction_v1_stop",
                  params: [upToken]
                })
              );
            return;
          }
          isActive = state.onGoingRequests.has(id2);
          if ("result" in parsed && state.onGoingRequests.get(id2)?.type === 0)
            state.activeChainHeads.add(parsed.result);
          state.onGoingRequests.delete(parsed.id);
        } else if ("params" in parsed) {
          const { subscription, result } = parsed.params;
          if (result?.event === "stop")
            state.activeChainHeads.delete(subscription);
        }
      }
      if (isActive && state.type !== 2)
        toConsumer(parsed);
    };
    const send = (msg) => {
      if (state.type === 2)
        return;
      if ("id" in msg) {
        const { method, id: id2, params } = msg;
        const [group, , methodName] = method.split("_");
        if (group === "transaction") {
          if (methodName === "stop") {
            const [synToken] = params;
            const active = state.activeBroadcasts.get(synToken);
            state.activeBroadcasts.delete(synToken);
            toConsumer(
              jsonRpcRsp({
                id: id2,
                result: null
              })
            );
            if (state.type === 0 && active && active.upToken) {
              state.connection.send(
                jsonRpcReq({
                  id: id2,
                  method,
                  params: [active.upToken]
                })
              );
            }
            return;
          }
          if (methodName === "broadcast") {
            const synToken = getOpaqueToken();
            state.activeBroadcasts.set(synToken, {
              tx: params[0],
              synToken
            });
            if (state.type === 0) {
              state.pendingBroadcasts.set(id2, synToken);
              state.connection.send(msg);
            }
            toConsumer(
              jsonRpcRsp({
                id: id2,
                result: synToken
              })
            );
            return;
          }
        }
      }
      if (state.type === 1) {
        state.pending.push(msg);
        return;
      }
      if (msg.method === "chainHead_v1_unfollow")
        state.activeChainHeads.delete(msg.params[0]);
      if ("id" in msg) {
        const { method, id: id2 } = msg;
        const [group, , methodName] = method.split("_");
        const ongoingMsg = group === "chainHead" ? methodName === "follow" ? {
          type: 0,
          msg
        } : { type: 1, id: id2 } : { type: 2, msg };
        state.onGoingRequests.set(id2, ongoingMsg);
      }
      state.connection.send(msg);
    };
    return {
      send,
      disconnect: () => {
        if (state.type === 2)
          return;
        if (state.type === 0)
          state.connection.disconnect();
        state = {
          type: 2
          /* Done */
        };
      },
      connect: (cb) => {
        if (state.type !== 1)
          throw new Error("Nonesense");
        const { pending, activeBroadcasts } = state;
        const onGoingRequests = /* @__PURE__ */ new Map();
        const activeChainHeads = /* @__PURE__ */ new Set();
        const onHalt = () => {
          const activeBroadcasts2 = state.type !== 2 ? state.activeBroadcasts : /* @__PURE__ */ new Map();
          activeBroadcasts2.forEach((x) => x.upToken = void 0);
          state = {
            type: 1,
            activeBroadcasts: activeBroadcasts2,
            pending: []
          };
          activeChainHeads.forEach((subscription) => {
            onMsgFromProvider(
              jsonRpcReq({
                method: "chainHead_v1_follow",
                params: {
                  subscription,
                  result: {
                    event: "stop",
                    internal: true
                  }
                }
              })
            );
          });
          activeChainHeads.clear();
          for (const x of onGoingRequests.values()) {
            if (x.type === 1)
              onMsgFromProvider(
                jsonRpcRsp({
                  id: x.id,
                  error: { code: -32603, message: "Internal error" }
                })
              );
            else
              send(x.msg);
          }
          onGoingRequests.clear();
        };
        state = {
          type: 0,
          connection: null,
          activeBroadcasts,
          pendingBroadcasts: /* @__PURE__ */ new Map(),
          onGoingRequests,
          activeChainHeads
        };
        state.connection = cb(onMsgFromProvider, onHalt);
        activeBroadcasts.forEach((broadcast) => {
          if (state.type === 0) {
            const id2 = getInternalId();
            state.pendingBroadcasts.set(id2, broadcast.synToken);
            state.connection.send(
              jsonRpcReq({
                id: id2,
                method: "transaction_v1_broadcast",
                params: [broadcast.tx]
              })
            );
          }
        });
        pending.forEach(send);
      }
    };
  };

  // node_modules/@polkadot-api/json-rpc-provider-proxy/dist/get-sync-provider.js
  var noop4 = () => {
  };
  var WAIT_BASE = 250;
  var getSyncProvider = (input) => (onMessage) => {
    let proxy = getProxy(onMessage);
    let lastHalt = Date.now();
    let consecutiveHalts = 0;
    let token;
    const getWaitTime = () => consecutiveHalts && 2 ** Math.min(5, consecutiveHalts) * WAIT_BASE;
    let stop = noop4;
    let startNow = () => {
      const token2 = setTimeout(() => {
        let isWaiting = true;
        const result = input((cb) => {
          isWaiting = false;
          stop = noop4;
          if (!cb)
            start();
          else if (proxy)
            proxy.connect((onMsg, onHalt) => {
              let isOn = true;
              return cb(onMsg, (e) => {
                if (isOn) {
                  isOn = false;
                  const diff = Date.now() - lastHalt;
                  consecutiveHalts += diff > WAIT_BASE + getWaitTime() ? -consecutiveHalts : 1;
                  lastHalt += diff;
                  onHalt(e);
                  start();
                }
              });
            });
        });
        if (isWaiting)
          stop = result;
      }, 0);
      stop = () => clearTimeout(token2);
    };
    const start = () => {
      token = setTimeout(startNow, getWaitTime());
    };
    startNow();
    return {
      send(msg) {
        proxy?.send(msg);
      },
      disconnect() {
        clearTimeout(token);
        stop();
        stop = noop4;
        proxy?.disconnect();
        proxy = null;
      }
    };
  };

  // node_modules/rxjs/dist/esm5/internal/util/identity.js
  function identity2(x) {
    return x;
  }

  // node_modules/@novasamatech/host-substrate-chain-connection/dist/helpers.js
  function noop5() {
  }

  // node_modules/@polkadot-api/ws-provider/dist/types.js
  var WsEvent = /* @__PURE__ */ ((WsEvent2) => {
    WsEvent2["CONNECTING"] = "CONNECTING";
    WsEvent2["CONNECTED"] = "CONNECTED";
    WsEvent2["ERROR"] = "ERROR";
    WsEvent2["CLOSE"] = "CLOSE";
    return WsEvent2;
  })(WsEvent || {});
  var SocketEvents = /* @__PURE__ */ ((SocketEvents2) => {
    SocketEvents2["CONNECTING"] = "CONNECTING";
    SocketEvents2["CONNECTED"] = "CONNECTED";
    SocketEvents2["TIMEOUT"] = "TIMEOUT";
    SocketEvents2["STALE"] = "STALE";
    SocketEvents2["ERROR"] = "ERROR";
    SocketEvents2["CLOSE"] = "CLOSE";
    SocketEvents2["DISCONNECT"] = "DISCONNECT";
    SocketEvents2["IN"] = "IN";
    SocketEvents2["OUT"] = "OUT";
    return SocketEvents2;
  })(SocketEvents || {});

  // node_modules/@polkadot-api/ws-provider/dist/get-async-provider.js
  var getAsyncProvider = (input) => (onMessage, _onHalt) => {
    let connection = null;
    let pending = [];
    const done = () => {
      stop();
      onHalt = stop = noop2;
      connection = void 0;
      pending = [];
    };
    let onHalt = (e) => {
      done();
      _onHalt(e);
    };
    let stop = input((cb) => {
      stop = noop2;
      if (!cb) {
        onHalt();
      } else {
        connection = cb(onMessage, onHalt);
        pending.forEach((x) => connection?.send(x));
        pending = [];
      }
    });
    return {
      send: (msg) => {
        if (connection)
          connection.send(msg);
        else if (connection === null)
          pending.push(msg);
      },
      disconnect: () => {
        const x = connection;
        done();
        x?.disconnect();
      }
    };
  };

  // node_modules/@polkadot-api/ws-provider/dist/with-socket.js
  var withSocket = (getWebsocket, heartbeatTimeout, connectionTimeout, logger) => {
    const logType = logger ? (type) => logger({ type }) : noop2;
    const logMsg = logger ? (type, msg) => logger({ type, msg }) : noop2;
    return getAsyncProvider((onReady) => {
      const [socket, onConnected] = getWebsocket();
      logger?.({ type: SocketEvents.CONNECTING, url: socket.url });
      let suicide = () => {
        suicide = noop2;
        cleanup();
        onReady(null);
      };
      let isFirst = true;
      let heartbeatToken;
      const heartbeat = () => {
        clearTimeout(heartbeatToken);
        const [time, event] = isFirst ? [connectionTimeout, SocketEvents.TIMEOUT] : [heartbeatTimeout, SocketEvents.STALE];
        isFirst = false;
        heartbeatToken = setTimeout(() => {
          logType(event);
          suicide({
            type: WsEvent.ERROR,
            event: { type: "timeout" }
          });
        }, time);
      };
      const stopTimeout = () => {
        clearTimeout(heartbeatToken);
      };
      heartbeat();
      let cleanup = () => {
        stopTimeout();
      };
      const onError = (event) => {
        logger?.({ type: SocketEvents.ERROR, error: event });
        suicide({
          type: WsEvent.ERROR,
          event
        });
      };
      const onClose = (event) => {
        logType(SocketEvents.CLOSE);
        suicide({
          type: WsEvent.CLOSE,
          event
        });
      };
      const disconnect = () => {
        logType(SocketEvents.DISCONNECT);
        cleanup();
        try {
          socket.addEventListener("error", noop2, { once: true });
          socket.close();
        } catch {
        }
      };
      const onOpen = () => {
        logType(SocketEvents.CONNECTED);
        onConnected();
        heartbeat();
        socket.removeEventListener("open", onOpen);
        onReady((onMsg, onHalt) => {
          cleanup = () => {
            cleanup = noop2;
            stopTimeout();
            socket.removeEventListener("error", onError);
            socket.removeEventListener("ping", heartbeat);
            socket.removeEventListener("message", _onMessage);
            socket.removeEventListener("close", onClose);
          };
          suicide = (e) => {
            suicide = noop2;
            cleanup();
            onHalt(e);
          };
          const _onMessage = (e) => {
            heartbeat();
            if (typeof e.data === "string") {
              logMsg(SocketEvents.IN, e.data);
              onMsg(JSON.parse(e.data));
            }
          };
          socket.addEventListener("ping", heartbeat);
          socket.addEventListener("message", _onMessage);
          socket.addEventListener("error", onError);
          socket.addEventListener("close", onClose);
          return {
            send(m) {
              const msg = JSON.stringify(m);
              logMsg(SocketEvents.OUT, msg);
              socket.send(msg);
            },
            disconnect
          };
        });
      };
      cleanup = () => {
        cleanup = noop2;
        stopTimeout();
        socket.removeEventListener("error", onError);
        socket.removeEventListener("close", onClose);
        socket.removeEventListener("open", onOpen);
      };
      socket.addEventListener("open", onOpen);
      socket.addEventListener("error", onError);
      return disconnect;
    });
  };

  // node_modules/@polkadot-api/ws-provider/dist/provider.js
  var defaultConfig = {
    onStatusChanged: noop2,
    timeout: 5e3,
    heartbeatTimeout: 4e4,
    middleware: identity2
  };
  var getWsProvider = (endpoints, config) => {
    const {
      onStatusChanged: _onStatuChanged,
      timeout,
      heartbeatTimeout,
      middleware,
      logger
    } = {
      ...defaultConfig,
      ...config
    };
    const actualEndpoints = Array.isArray(endpoints) ? endpoints : [endpoints];
    const WebsocketClass = config?.websocketClass ?? globalThis.WebSocket;
    if (!WebsocketClass)
      throw new Error("Missing WebSocket class");
    let idx = 0;
    let switchTo;
    let latestSocket = null;
    let status = { type: WsEvent.CLOSE, event: null };
    let prevUri;
    const onStatusChanged = (x) => _onStatuChanged(status = x);
    const socketProvider = middleware(
      withSocket(
        () => {
          prevUri = latestSocket?.url;
          const uri = switchTo ?? actualEndpoints[idx++ % actualEndpoints.length];
          switchTo = void 0;
          onStatusChanged({
            type: WsEvent.CONNECTING,
            uri
          });
          return [
            latestSocket = new WebsocketClass(uri),
            () => {
              onStatusChanged({
                type: WsEvent.CONNECTED,
                uri
              });
            }
          ];
        },
        heartbeatTimeout,
        timeout,
        logger
      )
    );
    const provider = (onMsg, onHalt) => socketProvider(onMsg, (event) => {
      onStatusChanged({
        type: WsEvent.ERROR,
        event
      });
      onHalt(event);
    });
    const result = getSyncProvider((onReady) => {
      if (!prevUri || latestSocket.url !== prevUri) {
        onReady(provider);
        return noop2;
      }
      const token = setTimeout(onReady, 250, provider);
      return () => {
        clearTimeout(token);
      };
    });
    const switchFn = (uri) => {
      if (status.type === WsEvent.CLOSE)
        return;
      switchTo = uri;
      if (status.type !== WsEvent.ERROR && latestSocket)
        latestSocket.close();
    };
    return Object.assign(result, { switch: switchFn, getStatus: () => status });
  };

  // node_modules/@novasamatech/host-substrate-chain-connection/dist/pauseController.js
  var createPauseController = () => {
    let paused = false;
    let destroyed = false;
    let base = null;
    let onMessage = null;
    let onHalt = null;
    let real = null;
    let buffer = [];
    let reinvocationPending = false;
    const connect = () => {
      if (!base || !onMessage || !onHalt)
        return;
      real = base(onMessage, onHalt);
      const q = buffer;
      buffer = [];
      for (const m of q)
        real.send(m);
    };
    const middleware = (b) => {
      base = b;
      return (onMsg, onH) => {
        reinvocationPending = false;
        destroyed = false;
        onMessage = onMsg;
        onHalt = onH;
        real = null;
        if (!paused)
          connect();
        return {
          send: (m) => real ? real.send(m) : buffer.push(m),
          disconnect: () => {
            destroyed = true;
            paused = false;
            buffer = [];
            real?.disconnect();
            real = null;
          }
        };
      };
    };
    const pause = () => {
      if (paused || destroyed)
        return;
      paused = true;
      if (!real || !onHalt)
        return;
      reinvocationPending = true;
      const r = real;
      real = null;
      r.disconnect();
      onHalt({ type: "paused" });
    };
    const resume = () => {
      if (destroyed || !paused)
        return;
      paused = false;
      if (!reinvocationPending)
        connect();
    };
    return { middleware, pause, resume, isPaused: () => paused };
  };

  // node_modules/@novasamatech/host-substrate-chain-connection/dist/subscriptionReplayProvider.js
  var isChainMethod = (method) => method.startsWith("chain_");
  var isSubscribeMethod = (method) => {
    if (isChainMethod(method))
      return false;
    const m = method.toLowerCase();
    return m.includes("subscribe") && !m.includes("unsubscribe");
  };
  var isUnsubscribeMethod = (method) => !isChainMethod(method) && method.toLowerCase().includes("unsubscribe");
  var withSubscriptionReplay = (provider, onReconnect) => (onMessage) => {
    const pendingSubscriptions = /* @__PURE__ */ new Map();
    const activeSubscriptions = /* @__PURE__ */ new Map();
    const currentToConsumer = /* @__PURE__ */ new Map();
    const removeSubscription = (consumerSubId) => {
      const sub = activeSubscriptions.get(consumerSubId);
      if (sub === void 0)
        return void 0;
      activeSubscriptions.delete(consumerSubId);
      currentToConsumer.delete(sub.currentSubId);
      const pending = pendingSubscriptions.get(sub.id);
      if (pending?.reconnectFor === consumerSubId)
        pendingSubscriptions.delete(sub.id);
      return sub;
    };
    const conn = provider((message) => {
      if (isResponse(message) && message.id != null && "result" in message && typeof message.result === "string") {
        const pending = pendingSubscriptions.get(message.id);
        if (pending !== void 0) {
          pendingSubscriptions.delete(message.id);
          const newSubId = message.result;
          if (pending.reconnectFor !== null) {
            const sub = activeSubscriptions.get(pending.reconnectFor);
            if (sub !== void 0) {
              currentToConsumer.delete(sub.currentSubId);
              sub.currentSubId = newSubId;
              currentToConsumer.set(newSubId, pending.reconnectFor);
            }
            return;
          }
          activeSubscriptions.set(newSubId, { id: message.id, payload: pending.payload, currentSubId: newSubId });
          currentToConsumer.set(newSubId, newSubId);
        }
        onMessage(message);
        return;
      }
      if (isRequest(message)) {
        const params = message.params;
        const incoming = params?.subscription;
        if (typeof incoming === "string") {
          const consumerSubId = currentToConsumer.get(incoming);
          if (consumerSubId !== void 0 && consumerSubId !== incoming) {
            onMessage({ ...message, params: { ...params, subscription: consumerSubId } });
            return;
          }
        }
      }
      onMessage(message);
    });
    const unsubReconnect = onReconnect(() => {
      for (const [, pending] of pendingSubscriptions) {
        if (pending.reconnectFor === null)
          conn.send(pending.payload);
      }
      for (const [consumerSubId, sub] of activeSubscriptions) {
        pendingSubscriptions.set(sub.id, { payload: sub.payload, reconnectFor: consumerSubId });
        conn.send(sub.payload);
      }
    });
    return {
      send(message) {
        if (isRequest(message)) {
          const { method, id: id2, params } = message;
          if (isSubscribeMethod(method)) {
            if (id2 != null)
              pendingSubscriptions.set(id2, { payload: message, reconnectFor: null });
          } else if (isUnsubscribeMethod(method)) {
            const consumerSubId = params?.[0];
            const sub = consumerSubId !== void 0 ? removeSubscription(consumerSubId) : void 0;
            if (sub !== void 0 && sub.currentSubId !== consumerSubId) {
              const rest = (params ?? []).slice(1);
              conn.send({ ...message, params: [sub.currentSubId, ...rest] });
              return;
            }
          }
        }
        conn.send(message);
      },
      disconnect() {
        pendingSubscriptions.clear();
        activeSubscriptions.clear();
        currentToConsumer.clear();
        unsubReconnect();
        conn.disconnect();
      }
    };
  };

  // node_modules/@novasamatech/host-substrate-chain-connection/dist/wsProvider.js
  var STATUS_BY_WS_EVENT = {
    [WsEvent.CONNECTING]: "connecting",
    [WsEvent.CONNECTED]: "connected",
    [WsEvent.ERROR]: "disconnected",
    [WsEvent.CLOSE]: "disconnected"
  };
  var createWsJsonRpcProvider = (options) => {
    let notifyReconnect = noop5;
    const onReconnect = (cb) => {
      notifyReconnect = cb;
      return () => {
        notifyReconnect = noop5;
      };
    };
    const pauseController = createPauseController();
    const baseProvider = getWsProvider(options.endpoints, {
      logger: options.logger,
      // Forward only when defined: getWsProvider merges via `{...defaults, ...config}`,
      // so an explicit `undefined` clobbers the library's 40 s default and Node's
      // setTimeout clamps undefined/Infinity to 1 ms — which would kill every socket
      // right after open and drive a reconnect loop.
      ...options.heartbeatTimeout !== void 0 && { heartbeatTimeout: options.heartbeatTimeout },
      ...options.connectionTimeout !== void 0 && { timeout: options.connectionTimeout },
      middleware: (inner) => pauseController.middleware(inner),
      websocketClass: options.websocketClass,
      onStatusChanged: (event) => {
        const status = STATUS_BY_WS_EVENT[event.type];
        if (status === "connected") {
          notifyReconnect();
        }
        options.onStatusChanged?.(status);
      }
    });
    const replayProvider = withSubscriptionReplay(baseProvider, onReconnect);
    return Object.assign(replayProvider, {
      pause: () => pauseController.pause(),
      resume: () => pauseController.resume()
    });
  };

  // src/connection-manager.ts
  var ConnectionManager = class {
    constructor(websocketClass) {
      this.connections = /* @__PURE__ */ new Map();
      this.websocketClass = websocketClass;
    }
    add(genesisHash, onMessage) {
      const entry = {
        urls: [],
        onMessage,
        provider: null,
        inner: null,
        buffer: []
      };
      this.connections.set(genesisHash, entry);
      return entry;
    }
    connect(entry, genesisHash) {
      const provider = createWsJsonRpcProvider({
        endpoints: entry.urls,
        websocketClass: this.websocketClass,
        onStatusChanged: (status) => {
          console.log("[chainConnection] status:", status, "genesisHash:", genesisHash);
        }
      });
      entry.provider = provider;
      entry.inner = provider(entry.onMessage);
      for (const msg of entry.buffer)
        entry.inner.send(msg);
      entry.buffer.length = 0;
    }
    disconnect(genesisHash) {
      this.connections.get(genesisHash)?.inner?.disconnect();
      this.connections.delete(genesisHash);
    }
    pauseAll() {
      console.log("[chainConnection] pausing all connections");
      for (const [, entry] of this.connections) {
        entry.inner?.disconnect();
        entry.inner = null;
        entry.provider = null;
      }
    }
    resumeAll() {
      console.log("[chainConnection] resuming all connections");
      for (const [genesisHash, entry] of this.connections) {
        if (!entry.inner && entry.urls.length > 0) {
          this.connect(entry, genesisHash);
        }
      }
    }
  };

  // src/index.ts
  var _nativeFetch = window.fetch.bind(window);
  var _NativeXMLHttpRequest = window.XMLHttpRequest;
  var _NativeWebSocket = window.WebSocket;
  var _BlockedWebSocket = new Proxy(window.WebSocket, {
    construct() {
      throw new TypeError("Network access is not allowed");
    }
  });
  function freezeAndDelete(obj, prop) {
    try {
      Object.defineProperty(obj, prop, {
        get: () => void 0,
        set() {
        },
        configurable: false
      });
    } catch {
      try {
        delete obj[prop];
      } catch {
      }
    }
  }
  function freezeValue(obj, prop, value) {
    try {
      Object.defineProperty(obj, prop, {
        get: () => value,
        set() {
        },
        configurable: false
      });
    } catch {
    }
  }
  freezeValue(window, "WebSocket", _BlockedWebSocket);
  freezeAndDelete(window, "RTCPeerConnection");
  freezeAndDelete(window, "EventSource");
  freezeValue(navigator, "sendBeacon", () => false);
  freezeAndDelete(window, "indexedDB");
  freezeAndDelete(window, "caches");
  try {
    Object.defineProperty(document, "cookie", {
      get: () => "",
      set: () => {
      },
      configurable: false
    });
  } catch {
  }
  freezeAndDelete(window, "SharedWorker");
  if (navigator.serviceWorker) {
    try {
      Object.defineProperty(navigator, "serviceWorker", {
        value: Object.freeze({
          register: () => {
            throw new Error("ServiceWorker is not available");
          }
        }),
        writable: false,
        configurable: false
      });
    } catch {
    }
  }
  var _createElement = document.createElement.bind(document);
  freezeValue(document, "createElement", (tagName, options) => {
    if (tagName.toLowerCase() === "iframe") {
      throw new Error("iframe creation is not allowed");
    }
    return _createElement(tagName, options);
  });
  window.__HOST_WEBVIEW_MARK__ = true;
  var { callNative, subscribeNative } = createNativeTransport((message) => {
    const json = JSON.stringify(message);
    window.webkit.messageHandlers.__container__.postMessage(json);
  });
  freezeValue(window, "fetch", async (input, init) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    const response = await callNative("allowNetworkAccess", { url });
    if (!response.allowed) {
      return Promise.reject(new TypeError("Network access is not allowed"));
    }
    return _nativeFetch(input, init);
  });
  freezeValue(window, "XMLHttpRequest", function XMLHttpRequest() {
    const xhr = new _NativeXMLHttpRequest();
    const _open = xhr.open.bind(xhr);
    xhr.open = function(method, url, ...rest) {
      const resolvedUrl = typeof url === "string" ? url : url.href;
      callNative("allowNetworkAccess", { url: resolvedUrl }).then((response) => {
        if (!response.allowed) {
          xhr.dispatchEvent(new Event("error"));
          xhr.abort();
          return;
        }
        _open(method, url, ...rest);
      });
    };
    return xhr;
  });
  var { port1, port2 } = new MessageChannel();
  window.__HOST_API_PORT__ = port1;
  var subscribers = /* @__PURE__ */ new Set();
  port2.onmessage = (event) => {
    for (const subscriber of subscribers) {
      subscriber(event.data);
    }
  };
  var containerProvider = {
    logger: console,
    isCorrectEnvironment: () => true,
    postMessage(message) {
      port2.postMessage(message, [message.buffer]);
    },
    subscribe(callback) {
      subscribers.add(callback);
      return () => {
        subscribers.delete(callback);
      };
    },
    dispose() {
      subscribers.clear();
    }
  };
  var container = createContainer(containerProvider);
  container.handleAccountGet((account, { ok: ok2, err: err2 }) => {
    return callNative("accountGet", { account }).then(
      (result) => ok2({
        publicKey: fromHex3(result.publicKey)
      }),
      (e) => err2(new RequestCredentialsErr.Unknown({ reason: String(e) }))
    );
  });
  container.handleGetUserId((_params, { ok: ok2, err: err2 }) => {
    return callNative("getUserId", {}).then(
      (result) => ok2({ primaryUsername: result.primaryUsername }),
      (e) => {
        const msg = String(e);
        if (msg.includes("NotConnected"))
          return err2(new GetUserIdErr.NotConnected());
        if (msg.includes("PermissionDenied"))
          return err2(new GetUserIdErr.PermissionDenied());
        return err2(new GetUserIdErr.Unknown({ reason: msg }));
      }
    );
  });
  container.handleAccountGetAlias((account, { ok: ok2, err: err2 }) => {
    return callNative("accountGetAlias", { account }).then(
      (result) => ok2({
        context: fromHex3(result.context),
        alias: fromHex3(result.alias)
      }),
      (e) => err2(new RequestCredentialsErr.Unknown({ reason: String(e) }))
    );
  });
  container.handleGetLegacyAccounts((_params, { ok: ok2, err: err2 }) => {
    return callNative("getNonProductAccounts", {}).then(
      (result) => ok2(result.map((acc) => ({
        publicKey: fromHex3(acc.publicKey),
        name: acc.name ?? void 0
      }))),
      (e) => err2(new RequestCredentialsErr.Unknown({ reason: String(e) }))
    );
  });
  container.handleFeatureSupported((params, { ok: ok2 }) => {
    switch (params.tag) {
      case "Chain":
        return callNative("chainSupported", { genesisHash: params.value }).then((supported) => ok2(supported)).catch(() => ok2(false));
      default:
        return ok2(false);
    }
  });
  var connectionManager = new ConnectionManager(_NativeWebSocket);
  container.handleChainConnection((genesisHash) => {
    return (onMessage) => {
      const entry = connectionManager.add(genesisHash, onMessage);
      callNative("chainNodes", { genesisHash }).then((urls) => {
        console.log("[chainConnection] genesisHash:", genesisHash, "urls:", urls);
        entry.urls = urls;
        connectionManager.connect(entry, genesisHash);
      });
      return {
        send(message) {
          if (entry.inner)
            entry.inner.send(message);
          else
            entry.buffer.push(message);
        },
        disconnect() {
          connectionManager.disconnect(genesisHash);
        }
      };
    };
  });
  window.__pauseConnections__ = () => connectionManager.pauseAll();
  window.__resumeConnections__ = () => connectionManager.resumeAll();
  container.handleSignPayload(async ({ account, payload }, { ok: ok2, err: err2 }) => {
    try {
      const result = await callNative("signPayload", { account, ...payload });
      return ok2({ signature: result.signature, signedTransaction: result.signedTx ?? void 0 });
    } catch {
      return err2(new SigningErr.Rejected());
    }
  });
  container.handleSignRaw(async ({ account, payload }, { ok: ok2, err: err2 }) => {
    try {
      const nativeData = payload.tag === "Bytes" ? { data: toHex2(payload.value) } : { payload: payload.value };
      const result = await callNative("signRaw", { account, ...nativeData });
      return ok2({ signature: result.signature, signedTransaction: result.signedTx ?? void 0 });
    } catch {
      return err2(new SigningErr.Rejected());
    }
  });
  container.handleCreateTransaction(async (payload, { ok: ok2, err: err2 }) => {
    try {
      const result = await callNative("createTransaction", {
        signer: payload.signer,
        genesisHash: toHex2(payload.genesisHash),
        callData: toHex2(payload.callData),
        extensions: payload.extensions.map((e) => ({
          id: e.id,
          explicit: toHex2(e.extra),
          implicit: toHex2(e.additionalSigned)
        })),
        txExtVersion: payload.txExtVersion
      });
      return ok2(fromHex3(result.signedTx));
    } catch (e) {
      return err2(new CreateTransactionErr.Unknown({ reason: String(e) }));
    }
  });
  container.handleAccountConnectionStatusSubscribe((_params, send, _interrupt) => {
    send("connected");
    return () => {
    };
  });
  container.handleThemeSubscribe((_params, send, _interrupt) => {
    return subscribeNative(
      "themeSubscribe",
      {},
      (result) => send({ name: { tag: "Custom", value: result.name }, variant: result.variant }),
      () => send({ name: { tag: "Default", value: void 0 }, variant: "Dark" })
    );
  });
  container.handleRequestLogin((_params, { ok: ok2 }) => {
    return ok2("alreadyConnected");
  });
  container.handleChatPostMessage(async (params, { ok: ok2, err: err2 }) => {
    const { payload } = params;
    const chatId = params.roomId;
    try {
      switch (payload.tag) {
        case "Text": {
          const result = await callNative("chatSendTextMessage", { text: payload.value, chatId });
          return ok2({ messageId: result.messageId });
        }
        case "Custom": {
          const result = await callNative("chatSendCustomMessage", {
            messageType: payload.value.messageType,
            payloadHex: toHex2(payload.value.payload),
            chatId
          });
          return ok2({ messageId: result.messageId });
        }
        default:
          return err2(new ChatMessagePostingErr.Unknown({
            reason: `Unsupported message type: ${payload.tag}`
          }));
      }
    } catch (e) {
      return err2(new ChatMessagePostingErr.Unknown({ reason: String(e) }));
    }
  });
  container.handleChatCreateRoom(async (params, { ok: ok2, err: err2 }) => {
    try {
      const result = await callNative("chatCreateRoom", params);
      return ok2({ status: result.status });
    } catch (e) {
      return err2({ reason: String(e) });
    }
  });
  container.handleChatListSubscribe((_params, send, _interrupt) => {
    const unsub = subscribeNative("chatSubscribeRooms", {}, (rooms) => {
      send(rooms);
    });
    return unsub;
  });
  var renderSubscriptions = /* @__PURE__ */ new Map();
  window.renderMessage = (messageType, payloadHex, messageId) => {
    renderSubscriptions.get(messageId)?.unsubscribe();
    const payload = fromHex3(payloadHex);
    const subscription = container.renderChatCustomMessage({ messageId, messageType, payload }, (node) => {
      const scaleHex = toHex2(CustomRendererNode.enc(node));
      callNative("chatRenderWidget", { messageId, scaleHex });
    });
    renderSubscriptions.set(messageId, subscription);
  };
  var chatActionSend = null;
  container.handleChatActionSubscribe((_params, send, _interrupt) => {
    chatActionSend = send;
    return () => {
      chatActionSend = null;
    };
  });
  window.dispatchChatAction = (roomId, messageId, actionId, payloadHex) => {
    chatActionSend?.({
      roomId,
      peer: "native",
      payload: {
        tag: "ActionTriggered",
        value: {
          messageId,
          actionId,
          payload: payloadHex ? fromHex3(payloadHex) : void 0
        }
      }
    });
  };
  window.dispatchUserMessage = (roomId, text) => {
    chatActionSend?.({
      roomId,
      peer: "native",
      payload: {
        tag: "MessagePosted",
        value: { tag: "Text", value: text }
      }
    });
  };
  container.handleStatementStoreSubscribe((filter, send, _interrupt) => {
    const topicsHex = filter.value.map((t) => toHex2(t));
    const wireFilter = filter.tag === "MatchAll" ? { matchAll: topicsHex } : { matchAny: topicsHex };
    const unsub = subscribeNative(
      "statementStoreSubscribe",
      { filter: wireFilter },
      (page) => {
        send({
          statements: page.statements.map((s) => ({
            proof: { tag: s.proof.tag, value: { signature: fromHex3(s.proof.signature), signer: fromHex3(s.proof.signer) } },
            decryptionKey: void 0,
            expiry: s.expiry != null ? BigInt(s.expiry) : void 0,
            channel: s.channel != null ? fromHex3(s.channel) : void 0,
            topics: s.topics.map((t) => fromHex3(t)),
            data: s.data != null ? fromHex3(s.data) : void 0
          })),
          isComplete: page.isComplete
        });
      }
    );
    return unsub;
  });
  container.handleStatementStoreCreateProof(async ([account, statement], { ok: ok2, err: err2 }) => {
    try {
      const result = await callNative("createStatementProof", {
        account,
        channel: statement.channel ? toHex2(statement.channel) : void 0,
        expiry: statement.expiry?.toString() ?? void 0,
        topics: statement.topics.map((t) => toHex2(t)),
        data: statement.data ? toHex2(statement.data) : void 0
      });
      return ok2({
        tag: result.tag,
        value: { signature: fromHex3(result.signature), signer: fromHex3(result.signer) }
      });
    } catch {
      return err2(new StatementProofErr.UnableToSign());
    }
  });
  container.handleStatementStoreSubmit(async (statement, { ok: ok2, err: err2 }) => {
    try {
      const proofValue = statement.proof.value;
      await callNative("statementStoreSubmit", {
        proof: {
          tag: statement.proof.tag,
          signature: toHex2(proofValue.signature),
          signer: toHex2(proofValue.signer)
        },
        channel: statement.channel ? toHex2(statement.channel) : void 0,
        expiry: statement.expiry?.toString() ?? void 0,
        topics: statement.topics.map((t) => toHex2(t)),
        data: statement.data ? toHex2(statement.data) : void 0
      });
      return ok2(void 0);
    } catch (e) {
      return err2(new GenericError({ reason: String(e) }));
    }
  });
  container.handleStatementStoreCreateProofAuthorized(async (statement, { ok: ok2, err: err2 }) => {
    try {
      const result = await callNative("createStatementProofAuthorized", {
        channel: statement.channel ? toHex2(statement.channel) : void 0,
        expiry: statement.expiry?.toString() ?? void 0,
        topics: statement.topics.map((t) => toHex2(t)),
        data: statement.data ? toHex2(statement.data) : void 0
      });
      return ok2({
        tag: result.tag,
        value: { signature: fromHex3(result.signature), signer: fromHex3(result.signer) }
      });
    } catch (e) {
      return err2(new StatementProofErr.UnableToSign());
    }
  });
  container.handleRequestResourceAllocation(async (resources, { ok: ok2, err: err2 }) => {
    try {
      const dtos = resources.map((r) => {
        switch (r.tag) {
          case "SmartContractAllowance":
            return { kind: r.tag, dest: r.value };
          case "StatementStoreAllowance":
          case "BulletinAllowance":
          case "AutoSigning":
            return { kind: r.tag };
        }
      });
      const result = await callNative("hostRequestResourceAllocation", { resources: dtos });
      const outcomes = result.outcomes.map((o) => ({
        tag: o.kind,
        value: void 0
      }));
      return ok2(outcomes);
    } catch (e) {
      return err2(new ResourceAllocationErr.Unknown({ reason: String(e) }));
    }
  });
  container.handlePreimageLookupSubscribe((hashHex, send, _interrupt) => {
    callNative("preimageLookup", { hash: hashHex }).then(
      (result) => send(result.data ? fromHex3(result.data) : null),
      () => send(null)
    );
    return () => {
    };
  });
  container.handlePreimageSubmit(async (data, { ok: ok2, err: err2 }) => {
    try {
      const result = await callNative("preimageSubmit", { data: toHex2(data) });
      return ok2(result.hash);
    } catch (e) {
      return err2(new PreimageSubmitErr.Unknown({ reason: String(e) }));
    }
  });
  container.handleDevicePermission(async (capability, { ok: ok2, err: err2 }) => {
    try {
      const result = await callNative("devicePermission", { capability });
      return ok2(result);
    } catch (e) {
      return err2(new GenericError({ reason: String(e) }));
    }
  });
  container.handlePermission(async (requests, { ok: ok2, err: err2 }) => {
    console.log("[handlePermission] raw requests:", JSON.stringify(requests));
    console.log("[handlePermission] isArray:", Array.isArray(requests));
    console.log("[handlePermission] typeof:", typeof requests);
    try {
      const payload = (Array.isArray(requests) ? requests : [requests]).map((r) => ({
        tag: r.tag,
        value: r.tag === "Remote" ? r.value : void 0
      }));
      console.log("[handlePermission] payload to native:", JSON.stringify(payload));
      const result = await callNative("remotePermission", payload);
      console.log("[handlePermission] native result:", JSON.stringify(result));
      return ok2(result);
    } catch (e) {
      console.log("[handlePermission] error:", String(e));
      return err2(new GenericError({ reason: String(e) }));
    }
  });
  container.handleLocalStorageRead((key, { ok: ok2, err: err2 }) => {
    return callNative("localStorageRead", { key }).then(
      (result) => ok2(result.value != null ? fromHex3(result.value) : void 0),
      (e) => err2(new StorageErr.Unknown({ reason: String(e) }))
    );
  });
  container.handleLocalStorageWrite(([key, value], { ok: ok2, err: err2 }) => {
    return callNative("localStorageWrite", { key, value: toHex2(value) }).then(
      () => ok2(void 0),
      (e) => err2(new StorageErr.Unknown({ reason: String(e) }))
    );
  });
  container.handleLocalStorageClear((key, { ok: ok2, err: err2 }) => {
    return callNative("localStorageClear", { key }).then(
      () => ok2(void 0),
      (e) => err2(new StorageErr.Unknown({ reason: String(e) }))
    );
  });
  container.handleNavigateTo((destination, { ok: ok2, err: err2 }) => {
    return callNative("navigateTo", { destination }).then(
      () => ok2(void 0),
      (e) => err2(new NavigateToErr.Unknown({ reason: String(e) }))
    );
  });
  container.handlePushNotification(async (params, { ok: ok2, err: err2 }) => {
    try {
      const scheduledAt = params.scheduledAt !== void 0 ? Number(params.scheduledAt) : void 0;
      const result = await callNative("pushNotification", {
        text: params.text,
        deeplink: params.deeplink,
        scheduledAtMs: scheduledAt
      });
      return ok2(result.notificationId);
    } catch (e) {
      const reason = String(e);
      if (reason.includes("Schedule limit reached")) {
        return err2(new PushNotificationError.ScheduleLimitReached());
      }
      return err2(new PushNotificationError.Unknown({ reason }));
    }
  });
  container.handlePushNotificationCancel(async (identifier, { ok: ok2, err: err2 }) => {
    try {
      await callNative("cancelPushNotification", { identifier });
      return ok2(void 0);
    } catch (e) {
      return err2(new GenericError({ reason: String(e) }));
    }
  });
  container.handleDeriveEntropy(async (key, { ok: ok2, err: err2 }) => {
    try {
      const result = await callNative("deriveEntropy", { key: toHex2(key) });
      return ok2(fromHex3(result.entropy));
    } catch (e) {
      return err2(new DeriveEntropyErr.Unknown({ reason: String(e) }));
    }
  });
  container.handlePaymentBalanceSubscribe((_params, send, interrupt) => {
    return subscribeNative(
      "paymentBalanceSubscribe",
      {},
      (payload) => {
        send({ available: BigInt(payload.available) });
      },
      () => interrupt(new PaymentBalanceErr.Unknown({ reason: "subscription interrupted" }))
    );
  });
  container.handlePaymentRequest(async (params, { ok: ok2, err: err2 }) => {
    try {
      const result = await callNative("paymentRequest", {
        amount: params.amount.toString(),
        destinationHex: toHex2(params.destination)
      });
      return ok2({ id: result.id });
    } catch (e) {
      const msg = String(e instanceof Error ? e.message : e);
      if (msg.includes("payment rejected"))
        return err2(new PaymentRequestErr.Rejected());
      if (msg.includes("insufficient balance"))
        return err2(new PaymentRequestErr.InsufficientBalance());
      return err2(new PaymentRequestErr.Unknown({ reason: msg }));
    }
  });
  container.handlePaymentTopUp(async (params, { ok: ok2, err: err2 }) => {
    try {
      const nativeParams = {
        amount: params.amount.toString(),
        sourceTag: params.source.tag
      };
      if (params.source.tag === "ProductAccount") {
        nativeParams.sourceDerivationIndex = params.source.value;
      } else if (params.source.tag === "PrivateKey") {
        nativeParams.sourceKeyHex = toHex2(params.source.value);
      } else if (params.source.tag === "Coins") {
        nativeParams.sourceKeyListHex = params.source.value.map((k) => toHex2(k));
      }
      await callNative("paymentTopUp", nativeParams);
      return ok2(void 0);
    } catch (e) {
      return err2(new PaymentTopUpErr.Unknown({ reason: String(e) }));
    }
  });
  container.handlePaymentStatusSubscribe((paymentId, send, interrupt) => {
    return subscribeNative(
      "paymentStatusSubscribe",
      { paymentId },
      (payload) => {
        if (payload.tag === "Processing")
          send({ tag: "Processing", value: void 0 });
        else if (payload.tag === "Completed")
          send({ tag: "Completed", value: void 0 });
        else
          send({ tag: "Failed", value: payload.value ?? "" });
      },
      () => interrupt(new PaymentStatusErr.Unknown({ reason: "subscription interrupted" }))
    );
  });
  console.log("Host container initialized");
})();
