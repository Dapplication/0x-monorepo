/*

  Copyright 2018 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity 0.4.24;
pragma experimental ABIEncoderV2;

import "../../protocol/Exchange/interfaces/IExchange.sol";
import "../../tokens/ERC721Token/IERC721Token.sol";
import "../../utils/LibBytes/LibBytes.sol";

contract CompliantForwarder {

    using LibBytes for bytes;

    bytes4 constant internal EXCHANGE_FILL_ORDER_SELECTOR = bytes4(keccak256("fillOrder((address,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,bytes,bytes),uint256,bytes)"));
    IExchange internal EXCHANGE;
    IERC721Token internal COMPLIANCE_TOKEN;

    bytes4 constant internal EXCHANGE_FILL_ORDER_SELECTOR_2 = 0xb4be83d5;

    constructor(address exchange, address complianceToken)
        public
    {
        EXCHANGE = IExchange(exchange);
        COMPLIANCE_TOKEN = IERC721Token(complianceToken);
    }

    function executeTransaction(
        uint256 salt,
        address signerAddress,
        bytes signedExchangeTransaction,
        bytes signature
    ) 
        external
    {
        // Validate `signedFillOrderTransaction`
        bytes4 selector = signedExchangeTransaction.readBytes4(0);
        address makerAddress = 0x00;
        assembly {
            function getMakerAddress(orderPtr) -> makerAddress {
                let orderOffset := calldataload(orderPtr)
                makerAddress := calldataload(orderOffset)
            }

            switch selector
            case 0xb4be83d500000000000000000000000000000000000000000000000000000000 {
                let exchangeTxPtr := calldataload(0x44)

                // Add 0x20 for length offset and 0x04 for selector offset
                let orderPtrRelativeToExchangeTx := calldataload(add(0x4, add(exchangeTxPtr, 0x24))) // 0x60
                let orderPtr := add(0x4,add(exchangeTxPtr, add(0x24, orderPtrRelativeToExchangeTx)))
                
                makerAddress := calldataload(orderPtr)
                
                
                //makerAddress := getMakerAddress(orderPtr)
            }
            default {
                // revert(0, 100)
            }
        }
        
        /*
        if (selector != 0xb4be83d5) {
            revert("EXCHANGE_TRANSACTION_NOT_FILL_ORDER");
        }*/
        
        // Taker must be compliant
        require(
            COMPLIANCE_TOKEN.balanceOf(signerAddress) > 0,
            "TAKER_UNVERIFIED"
        );

        // Extract maker address from fill order transaction and ensure maker is compliant
        // Below is the table of calldata offsets into a fillOrder transaction.
        /**
                    ### parameters 
            0x00      ptr<order>                                                                      
            0x20      takerAssetFillAmount                                                            
            0x40      ptr<signature>                                                                  
                    ### order                                                                           
            0x60      makerAddress                                                                    
            0x80      takerAddress                                                                    
            0xa0      feeRecipientAddress                                                             
            0xc0      senderAddress                                                                   
            0xe0      makerAssetAmount                                                                
            0x100     takerAssetAmount                                                                
            0x120     makerFee                                                                        
            0x140     takerFee                                                                        
            0x160     expirationTimeSeconds                                                           
            0x180     salt                                                                            
            0x1a0     ptr<makerAssetData>                                                             
            0x1c0     ptr<takerAssetData>                                                             
            0x1e0     makerAssetData                                                                  
            *         takerAssetData                                                                  
            *         signature
            ------------------------------
            * Context-dependent offsets; unknown at compile time.
        */
        // Add 0x4 to a given offset to account for the fillOrder selector prepended to `signedFillOrderTransaction`.
        // Add 0xc to the makerAddress since abi-encoded addresses are left padded with 12 bytes.
        // Putting this together: makerAddress = 0x60 + 0x4 + 0xc = 0x70
        //address makerAddress = signedExchangeTransaction.readAddress(0x70);
        require(
            COMPLIANCE_TOKEN.balanceOf(makerAddress) > 0, 
            "MAKER_UNVERIFIED"
        );
        
        // All entities are verified. Execute fillOrder.
        EXCHANGE.executeTransaction(
            salt,
            signerAddress,
            signedExchangeTransaction,
            signature
        );
    }
}