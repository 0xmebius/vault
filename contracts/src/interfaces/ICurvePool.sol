// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IPlainPool {
    function coins(uint256 i) external view returns (address);
    function lp_token() external view returns (address);
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns (uint256 actual_dy);
    
    function add_liquidity(uint256[2] calldata _amounts, uint256 _min_mint_amount) external returns (uint256 actualMinted);
    function add_liquidity(uint256[3] calldata _amounts, uint256 _min_mint_amount) external returns (uint256 actualMinted);
    function add_liquidity(uint256[4] calldata _amounts, uint256 _min_mint_amount) external returns (uint256 actualMinted);
    function add_liquidity(uint256[5] calldata _amounts, uint256 _min_mint_amount) external returns (uint256 actualMinted);

    function remove_liquidity(uint256 _amount, uint256[2] calldata _min_amounts) external returns (uint256[2] calldata actualWithdrawn);
    function remove_liquidity(uint256 _amount, uint256[3] calldata _min_amounts) external returns (uint256[3] calldata actualWithdrawn);
    function remove_liquidity(uint256 _amount, uint256[4] calldata _min_amounts) external returns (uint256[4] calldata actualWithdrawn);
    function remove_liquidity(uint256 _amount, uint256[5] calldata _min_amounts) external returns (uint256[5] calldata actualWithdrawn);

    function remove_liquidity_imbalance(uint256[2] calldata _amounts, uint256 _max_burn_amount) external returns (uint256 actualBurned);
    function remove_liquidity_imbalance(uint256[3] calldata _amounts, uint256 _max_burn_amount) external returns (uint256 actualBurned);
    function remove_liquidity_imbalance(uint256[4] calldata _amounts, uint256 _max_burn_amount) external returns (uint256 actualBurned);
    function remove_liquidity_imbalance(uint256[5] calldata _amounts, uint256 _max_burn_amount) external returns (uint256 actualBurned);

    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 _min_amount) external returns (uint256 actualWithdrawn);
}

interface ILendingPool {
    function coins(uint256 i) external view returns (address);
    function underlying_coins(uint256 i) external view returns (address);
    function lp_token() external view returns (address);
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns (uint256 actual_dy);
    function exchange_underlying(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns (uint256 actual_dy);


    function add_liquidity(uint256[2] calldata _amounts, uint256 _min_mint_amount) external returns (uint256 actualMinted);
    function add_liquidity(uint256[3] calldata _amounts, uint256 _min_mint_amount) external returns (uint256 actualMinted);
    function add_liquidity(uint256[4] calldata _amounts, uint256 _min_mint_amount) external returns (uint256 actualMinted);
    function add_liquidity(uint256[5] calldata _amounts, uint256 _min_mint_amount) external returns (uint256 actualMinted);

    function add_liquidity(uint256[2] calldata _amounts, uint256 _min_mint_amount, bool _use_underlying) external returns (uint256 actualMinted);
    function add_liquidity(uint256[3] calldata _amounts, uint256 _min_mint_amount, bool _use_underlying) external returns (uint256 actualMinted);
    function add_liquidity(uint256[4] calldata _amounts, uint256 _min_mint_amount, bool _use_underlying) external returns (uint256 actualMinted);
    function add_liquidity(uint256[5] calldata _amounts, uint256 _min_mint_amount, bool _use_underlying) external returns (uint256 actualMinted);

    function remove_liquidity(uint256 _amount, uint256[2] calldata _min_amounts) external returns (uint256[2] calldata actualWithdrawn);
    function remove_liquidity(uint256 _amount, uint256[3] calldata _min_amounts) external returns (uint256[3] calldata actualWithdrawn);
    function remove_liquidity(uint256 _amount, uint256[4] calldata _min_amounts) external returns (uint256[4] calldata actualWithdrawn);
    function remove_liquidity(uint256 _amount, uint256[5] calldata _min_amounts) external returns (uint256[5] calldata actualWithdrawn);

    function remove_liquidity_imbalance(uint256[2] calldata _amounts, uint256 _max_burn_amount) external returns (uint256 actualBurned);
    function remove_liquidity_imbalance(uint256[3] calldata _amounts, uint256 _max_burn_amount) external returns (uint256 actualBurned);
    function remove_liquidity_imbalance(uint256[4] calldata _amounts, uint256 _max_burn_amount) external returns (uint256 actualBurned);
    function remove_liquidity_imbalance(uint256[5] calldata _amounts, uint256 _max_burn_amount) external returns (uint256 actualBurned);

    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 _min_amount) external returns (uint256 actualWithdrawn);
}

interface IMetaPool {
    function coins(uint256 i) external view returns (address);
    function base_coins(uint256 i) external view returns (address);
    function base_pool() external view returns (address);
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns (uint256 actual_dy);
    function exchange_underlying(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns (uint256 actual_dy);


    function add_liquidity(uint256[2] calldata _amounts, uint256 _min_mint_amount) external returns (uint256 actualMinted);
    function add_liquidity(uint256[3] calldata _amounts, uint256 _min_mint_amount) external returns (uint256 actualMinted);
    function add_liquidity(uint256[4] calldata _amounts, uint256 _min_mint_amount) external returns (uint256 actualMinted);
    function add_liquidity(uint256[5] calldata _amounts, uint256 _min_mint_amount) external returns (uint256 actualMinted);

    function remove_liquidity(uint256 _amount, uint256[2] calldata _min_amounts) external returns (uint256[2] calldata actualWithdrawn);
    function remove_liquidity(uint256 _amount, uint256[3] calldata _min_amounts) external returns (uint256[3] calldata actualWithdrawn);
    function remove_liquidity(uint256 _amount, uint256[4] calldata _min_amounts) external returns (uint256[4] calldata actualWithdrawn);
    function remove_liquidity(uint256 _amount, uint256[5] calldata _min_amounts) external returns (uint256[5] calldata actualWithdrawn);

    function remove_liquidity_imbalance(uint256[2] calldata _amounts, uint256 _max_burn_amount) external returns (uint256 actualBurned);
    function remove_liquidity_imbalance(uint256[3] calldata _amounts, uint256 _max_burn_amount) external returns (uint256 actualBurned);
    function remove_liquidity_imbalance(uint256[4] calldata _amounts, uint256 _max_burn_amount) external returns (uint256 actualBurned);
    function remove_liquidity_imbalance(uint256[5] calldata _amounts, uint256 _max_burn_amount) external returns (uint256 actualBurned);

    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 _min_amount) external returns (uint256 actualWithdrawn);
}