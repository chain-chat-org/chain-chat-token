// SPDX-License-Identifier: SimPL-2.0
pragma solidity  ^0.7.5;

/**
 * Math operations with safety checks
 */
contract SafeMath {
  function safeMul(uint256 a, uint256 b) pure internal returns (uint256) {
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeDiv(uint256 a, uint256 b) pure internal returns (uint256) {
    assert(b > 0);
    uint256 c = a / b;
    assert(a == b * c + a % b);
    return c;
  }

  function safeSub(uint256 a, uint256 b) pure internal returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function safeAdd(uint256 a, uint256 b) pure internal returns (uint256) {
    uint256 c = a + b;
    assert(c>=a && c>=b);
    return c;
  }
}

library TransferHelper {
    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }
}


/*
wcct

1.cct和wcct双向1:1兑换,免销毁。
2.wcct归集到交易所免销毁，交易转出免销毁，便于交易所接入。
3.日常转账5%不变.

*/
contract token is SafeMath{
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    uint256 public totalBurn;
    address payable public owner;
    address public miner;
    address public token_cct = 0xE8377eCb0F32f0C16025d5cF360D6C9e2EA66Adf;
    bool public is_mint = true;

    /* This creates an array with all balances */
    mapping (address => uint256) public balanceOf;
    mapping (address => uint256) public freezeOf;
    mapping (address => bool)  public whitelist;
    mapping (address => mapping (address => uint256)) public allowance;

    /* This generates a public event on the blockchain that will notify clients */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /* This notifies clients about the amount burnt */
    event Burn(address indexed from, uint256 value);
	
	/* This notifies clients about the amount frozen */
    event Freeze(address indexed from, uint256 value);
	
	/* This notifies clients about the amount unfrozen */
    event Unfreeze(address indexed from, uint256 value);

    
    event  Deposit(address indexed dst, uint wad);
    event  Withdrawal(address indexed src, uint wad);

    /* Initializes contract with initial supply tokens to the creator of the contract */
    constructor(
        uint256 initialSupply,
        string memory tokenName,
        uint8 decimalUnits,
        string memory tokenSymbol
        ) {
        balanceOf[msg.sender] = initialSupply * 10 ** uint256(decimalUnits);              // Give the creator all initial tokens
        totalSupply = initialSupply * 10 ** uint256(decimalUnits);// Update total supply
        name = tokenName;                                   // Set the name for display purposes
        symbol = tokenSymbol;                               // Set the symbol for display purposes
        decimals = decimalUnits;                            // Amount of decimals for display purposes
        owner = msg.sender;
        miner = msg.sender;
    }

    //托管
    function depositToken(uint256 amount) public {
        require(amount >= 0);
        TransferHelper.safeTransferFrom(token_cct, msg.sender, address(this), amount);
        balanceOf[msg.sender]  += amount;
        emit Deposit(msg.sender, amount);
    }

    //提现
    function withdrawToken(uint256 amount) public {
        require(balanceOf[msg.sender] >= amount);
        require(amount >= 0);
        balanceOf[msg.sender] -= amount;
        TransferHelper.safeTransfer(token_cct,msg.sender,amount);
        Withdrawal(msg.sender, amount);
    }


    /* Send coins */
    function transfer(address _to, uint256 _value) public returns(bool success) {
        require(_to != address(0)); // Prevent transfer to 0x0 address. Use burn() instead
        require(_value > 0);
        require(msg.sender != _to);//自己不能转给自己

        uint fee = transfer_fee(msg.sender,_to, _value);
        uint sub_value = SafeMath.safeAdd(fee, _value); //扣除余额需要计算手续费

        require(balanceOf[msg.sender] >= sub_value);//需要计算加上手续费后是否够
        if (balanceOf[_to] + _value < balanceOf[_to]) revert("overflows"); // Check for overflows

        balanceOf[msg.sender] = SafeMath.safeSub(balanceOf[msg.sender], sub_value);// Subtract from the sender
        balanceOf[_to] = SafeMath.safeAdd(balanceOf[_to], _value);                            // Add the same to the recipient
        totalSupply -= fee;//总量减少手续费
        emit Transfer(msg.sender, _to, _value);                   // Notify anyone listening that this transfer took place
        if (fee > 0)
        {
            emit Burn(msg.sender, fee);
            totalBurn += fee;
        }
        return true;
    }

    /* Allow another contract to spend some tokens in your behalf */
    function approve(address _spender, uint256 _value) public returns (bool success) {
		if (_value <= 0) revert(); 
        allowance[msg.sender][_spender] = _value;
        return true;
    }

    function transfer_fee(address _from,address _to, uint256 _value) public view returns(uint256 fee) {
        if(whitelist[_from])
            return 0;
        if(whitelist[_to])
            return 0;
        uint8 scale = 5;// n/100
        uint256 _fee = _value * scale / 100;
        return _fee;
    }

    /* A contract attempts to get the coins */
    function transferFrom(address _from, address _to, uint256 _value) public returns(bool success)  {
        if (_to == address(0)) revert();                                // Prevent transfer to 0x0 address. Use burn() instead
        if (_value <= 0) revert();
        require(_from != _to);//自己不能转给自己

        uint fee = transfer_fee(msg.sender,_to,_value);
        uint sub_value = SafeMath.safeAdd(fee, _value);


        if (balanceOf[_from] < sub_value) revert();                 // Check if the sender has enough
        if (balanceOf[_to] + _value < balanceOf[_to]) revert();  // Check for overflows
        if (sub_value > allowance[_from][msg.sender]) revert();     // Check allowance

        balanceOf[_from] = SafeMath.safeSub(balanceOf[_from], sub_value);                           // Subtract from the sender
        balanceOf[_to] = SafeMath.safeAdd(balanceOf[_to], _value);                             // Add the same to the recipient
        allowance[_from][msg.sender] = SafeMath.safeSub(allowance[_from][msg.sender], sub_value);
        totalSupply -= fee;//总量减少手续费
        emit Transfer(_from, _to, _value);
        if (fee > 0)
        {
            emit Burn(msg.sender, fee);
            totalBurn += fee;
        }
        return true;
    }

    //永久关闭mint
    function stopMint() public{
        require(msg.sender == owner);
        is_mint = false;
    }

    function mint(address account, uint256 amount) public {
        require(miner == msg.sender, "not miner");
        require(is_mint);

        totalSupply += amount;
        balanceOf[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function burn(uint256 _value) public returns (bool success)  {
        if (balanceOf[msg.sender] < _value) revert();            // Check if the sender has enough
		if (_value <= 0) revert(); 
        balanceOf[msg.sender] = SafeMath.safeSub(balanceOf[msg.sender], _value);                      // Subtract from the sender
        totalSupply = SafeMath.safeSub(totalSupply,_value);                                // Updates totalSupply
        Burn(msg.sender, _value);
        totalBurn += _value;
        return true;
    }
	
	function freeze(uint256 _value) public returns (bool success)  {
        if (balanceOf[msg.sender] < _value) revert();            // Check if the sender has enough
		if (_value <= 0) revert(); 
        balanceOf[msg.sender] = SafeMath.safeSub(balanceOf[msg.sender], _value);                      // Subtract from the sender
        freezeOf[msg.sender] = SafeMath.safeAdd(freezeOf[msg.sender], _value);                                // Updates totalSupply
        Freeze(msg.sender, _value);
        return true;
    }
	
	function unfreeze(uint256 _value) public returns (bool success) {
        if (freezeOf[msg.sender] < _value) revert();            // Check if the sender has enough
		if (_value <= 0) revert(); 
        freezeOf[msg.sender] = SafeMath.safeSub(freezeOf[msg.sender], _value);                      // Subtract from the sender
		balanceOf[msg.sender] = SafeMath.safeAdd(balanceOf[msg.sender], _value);
        Unfreeze(msg.sender, _value);
        return true;
    }
	
	// transfer balance to owner
	function withdrawQKI(uint256 amount) public{
		require(msg.sender == owner);
		owner.transfer(amount);
	}

    function setOwner(address payable newOwner) public{
        require(msg.sender == owner);
        owner = newOwner;
    }

    function setMiner(address newMiner) public{
        require(msg.sender == owner);
        miner = newMiner;
    }

    function setWhitelist(address account) public{
        require(msg.sender == owner);

        whitelist[account] = !whitelist[account];
    }
	
	// can accept ether
	receive() payable  external  {
    }
}