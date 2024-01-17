// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

library GatewayIndex {

    uint8 constant S_CUMULATIVEPNLONGATEWAY       = 1; // Cumulative pnl on Gateway
    uint8 constant S_LIQUIDITYTIME                = 2; // Last timestamp when liquidity updated
    uint8 constant S_TOTALLIQUIDITY               = 3; // Total liquidity on d-chain
    uint8 constant S_CUMULATIVETIMEPERLIQUIDITY   = 4; // Cumulavie time per liquidity
    uint8 constant S_GATEWAYREQUESTID             = 5; // Gateway request id
    uint8 constant S_DCHAINEXECUTIONFEEPERREQUEST = 6; // dChain execution fee for executing request on dChain
    uint8 constant S_TOTALICHAINEXECUTIONFEE      = 7; // Total iChain execution fee paid by all requests

    uint8 constant B_VAULT             = 1; // BToken vault address
    uint8 constant B_ORACLEID          = 2; // BToken oracle id
    uint8 constant B_COLLATERALFACTOR  = 3; // BToken collateral factor

    uint8 constant D_REQUESTID                          = 1;  // Lp/Trader request id
    uint8 constant D_BTOKEN                             = 2;  // Lp/Trader bToken
    uint8 constant D_B0AMOUNT                           = 3;  // Lp/Trader b0Amount
    uint8 constant D_LASTCUMULATIVEPNLONENGINE          = 4;  // Lp/Trader last cumulative pnl on engine
    uint8 constant D_LIQUIDITY                          = 5;  // Lp liquidity
    uint8 constant D_CUMULATIVETIME                     = 6;  // Lp cumulative time
    uint8 constant D_LASTCUMULATIVETIMEPERLIQUIDITY     = 7;  // Lp last cumulative time per liquidity
    uint8 constant D_SINGLEPOSITION                     = 8;  // Td single position flag
    uint8 constant D_LASTREQUESTICHAINEXECUTIONFEE      = 9;  // User last request's iChain execution fee
    uint8 constant D_CUMULATIVEUNUSEDICHAINEXECUTIONFEE = 10; // User cumulaitve iChain execution fee for requests cannot be finished, users can claim back

    uint256 constant ACTION_REQUESTADDLIQUIDITY         = 1;
    uint256 constant ACTION_REQUESTREMOVELIQUIDITY      = 2;
    uint256 constant ACTION_REQUESTREMOVEMARGIN         = 3;
    uint256 constant ACTION_REQUESTTRADE                = 4;
    uint256 constant ACTION_REQUESTTRADEANDREMOVEMARGIN = 5;

}
