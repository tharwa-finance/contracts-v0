import { EndpointId } from "@layerzerolabs/lz-definitions";
const holesky_testnetContract = {
    eid: EndpointId.HOLESKY_V2_TESTNET,
    contractName: "thUSD"
};
const sepolia_testnetContract = {
    eid: EndpointId.SEPOLIA_V2_TESTNET,
    contractName: "thUSD"
};
export default { contracts: [{ contract: holesky_testnetContract }, { contract: sepolia_testnetContract }], connections: [{ from: holesky_testnetContract, to: sepolia_testnetContract, config: { sendLibrary: "0x21F33EcF7F65D61f77e554B4B4380829908cD076", receiveLibraryConfig: { receiveLibrary: "0xbAe52D605770aD2f0D17533ce56D146c7C964A0d", gracePeriod: 0 }, sendConfig: { executorConfig: { maxMessageSize: 10000, executor: "0xBc0C24E6f24eC2F1fd7E859B8322A1277F80aaD5" }, ulnConfig: { confirmations: 1, requiredDVNs: ["0x3E43f8ff0175580f7644DA043071c289DDf98118"], optionalDVNs: [], optionalDVNThreshold: 0 } }, receiveConfig: { ulnConfig: { confirmations: 2, requiredDVNs: ["0x3E43f8ff0175580f7644DA043071c289DDf98118"], optionalDVNs: [], optionalDVNThreshold: 0 } } } }, { from: sepolia_testnetContract, to: holesky_testnetContract, config: { sendLibrary: "0xcc1ae8Cf5D3904Cef3360A9532B477529b177cCE", receiveLibraryConfig: { receiveLibrary: "0xdAf00F5eE2158dD58E0d3857851c432E34A3A851", gracePeriod: 0 }, sendConfig: { executorConfig: { maxMessageSize: 10000, executor: "0x718B92b5CB0a5552039B593faF724D182A881eDA" }, ulnConfig: { confirmations: 2, requiredDVNs: ["0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193"], optionalDVNs: [], optionalDVNThreshold: 0 } }, receiveConfig: { ulnConfig: { confirmations: 1, requiredDVNs: ["0x8eebf8b423B73bFCa51a1Db4B7354AA0bFCA9193"], optionalDVNs: [], optionalDVNThreshold: 0 } } } }] };
