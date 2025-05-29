// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PDPListener, PDPVerifier} from "../src/PDPVerifier.sol";
import {SimplePDPServiceWithPayments} from "../src/SimplePDPServiceWithPayments.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
import {Cids} from "../src/Cids.sol";
import {Payments, IArbiter} from "@fws-payments/Payments.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Mock implementation of the USDFC token
contract MockERC20 is IERC20, IERC20Metadata {
    string private _name = "USD Filecoin";
    string private _symbol = "USDFC";
    uint8 private _decimals = 6;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    constructor() {
        _mint(msg.sender, 1000000 * 10**_decimals); // Mint 1 million tokens to deployer
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        
        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, msg.sender, currentAllowance - amount);
        
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;
        
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}

// MockPDPVerifier is used to simulate the PDPVerifier for our tests
contract MockPDPVerifier {
    uint256 public nextProofSetId = 1;
    
    event ProofSetCreated(uint256 indexed setId, address indexed owner);

    // Basic implementation to create proof sets and call the listener
    function createProofSet(address listenerAddr, bytes calldata extraData) public payable returns (uint256) {
        uint256 setId = nextProofSetId++;
        
        // Call the listener if specified
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).proofSetCreated(setId, msg.sender, extraData);
        }
        
        emit ProofSetCreated(setId, msg.sender);
        return setId;
    }
}

contract SimplePDPServiceWithPaymentsTest is Test {
    // Contracts
    SimplePDPServiceWithPayments public pdpServiceWithPayments;
    MockPDPVerifier public mockPDPVerifier;
    Payments public payments;
    MockERC20 public mockUSDFC;
    
    // Test accounts
    address public deployer; 
    address public client;
    address public storageProvider;
    
    // Test parameters
    uint256 public initialOperatorCommissionBps = 500; // 5%
    uint256 public proofSetId;
    bytes public extraData;
    
    // Events from Payments contract to verify
    event RailCreated(uint256 railId, address token, address from, address to, address arbiter, uint256 commissionRateBps);
    
    function setUp() public {
        // Setup test accounts
        deployer = address(this);
        client = address(0x1);
        storageProvider = address(0x2);
        
        // Fund test accounts
        vm.deal(deployer, 100 ether);
        vm.deal(client, 100 ether);
        vm.deal(storageProvider, 100 ether);
        
        // Deploy mock contracts
        mockUSDFC = new MockERC20();
        mockPDPVerifier = new MockPDPVerifier();
        
        // Deploy actual Payments contract
        Payments paymentsImpl = new Payments();
        bytes memory paymentsInitData = abi.encodeWithSelector(Payments.initialize.selector);
        MyERC1967Proxy paymentsProxy = new MyERC1967Proxy(address(paymentsImpl), paymentsInitData);
        payments = Payments(address(paymentsProxy));
        
        // Transfer tokens to client for payment
        mockUSDFC.transfer(client, 10000 * 10**mockUSDFC.decimals());
        
        // Deploy SimplePDPServiceWithPayments with proxy
        SimplePDPServiceWithPayments pdpServiceImpl = new SimplePDPServiceWithPayments();
        bytes memory initializeData = abi.encodeWithSelector(
            SimplePDPServiceWithPayments.initialize.selector,
            address(mockPDPVerifier),
            address(payments),
            address(mockUSDFC),
            initialOperatorCommissionBps
        );
        
        MyERC1967Proxy pdpServiceProxy = new MyERC1967Proxy(address(pdpServiceImpl), initializeData);
        pdpServiceWithPayments = SimplePDPServiceWithPayments(address(pdpServiceProxy));
    }
    
    function testInitialState() public view {
        assertEq(pdpServiceWithPayments.pdpVerifierAddress(), address(mockPDPVerifier), "PDP verifier address should be set correctly");
        assertEq(pdpServiceWithPayments.paymentsContractAddress(), address(payments), "Payments contract address should be set correctly");
        assertEq(pdpServiceWithPayments.usdFcTokenAddress(), address(mockUSDFC), "USDFC token address should be set correctly");
        assertEq(pdpServiceWithPayments.operatorCommissionBps(), initialOperatorCommissionBps, "Operator commission should be set correctly");
        assertEq(pdpServiceWithPayments.tokenDecimals(), mockUSDFC.decimals(), "Token decimals should be correct");
        
        // Check fee constants are correctly calculated based on token decimals
        uint256 expectedProofSetCreationFee = (1 * 10 ** mockUSDFC.decimals()) / 10; // 0.1 USDFC
        assertEq(pdpServiceWithPayments.PROOFSET_CREATION_FEE(), expectedProofSetCreationFee, "Proof set creation fee should be set correctly");
    }
    
    function testCreateProofSetCreatesRailAndChargesFee() public {
        // Prepare ExtraData
        SimplePDPServiceWithPayments.ProofSetCreateData memory createData = SimplePDPServiceWithPayments.ProofSetCreateData({
            metadata: "Test Proof Set",
            payer: client
        });
        
        // Encode the extra data
        extraData = abi.encode(createData);
        
        // Client needs to approve the PDP Service to create a payment rail
        vm.startPrank(client);
        // Set operator approval for the PDP service in the Payments contract
        payments.setOperatorApproval(
            address(mockUSDFC),
            address(pdpServiceWithPayments),
            true,     // approved
            1000e6,   // rate allowance (1000 USDFC)
            1000e6    // lockup allowance (1000 USDFC)
        );
        
        // Client deposits funds to the Payments contract for the one-time fee
        uint256 depositAmount = 10 * pdpServiceWithPayments.PROOFSET_CREATION_FEE(); // 10x the required fee
        mockUSDFC.approve(address(payments), depositAmount);
        payments.deposit(address(mockUSDFC), client, depositAmount);
        vm.stopPrank();

        // Get account balances before creating proof set
        (uint256 clientFundsBefore, ) = getAccountInfo(address(mockUSDFC), client);
        (uint256 spFundsBefore, ) = getAccountInfo(address(mockUSDFC), storageProvider);
        
        // Expect RailCreated event when creating the proof set
        vm.expectEmit(true, true, true, true);
        emit SimplePDPServiceWithPayments.ProofSetRailCreated(1, 1, client, storageProvider);
        
        // Create a proof set as the storage provider
        vm.startPrank(storageProvider);
        uint256 newProofSetId = mockPDPVerifier.createProofSet(address(pdpServiceWithPayments), extraData);
        vm.stopPrank();
        
        // Get the rail ID from the PDP service
        uint256 railId = pdpServiceWithPayments.getProofSetRailId(newProofSetId);
        
        // Verify a valid rail ID was created
        assertTrue(railId > 0, "Rail ID should be non-zero");
        
        // Verify proof set info was stored correctly
        (address payer, address payee) = pdpServiceWithPayments.getProofSetParties(newProofSetId);
        assertEq(payer, client, "Payer should be set to client");
        assertEq(payee, storageProvider, "Payee should be set to storage provider");
        
        // Verify metadata was stored correctly
        string memory metadata = pdpServiceWithPayments.getProofSetMetadata(newProofSetId);
        assertEq(metadata, "Test Proof Set", "Metadata should be stored correctly");
        
        // Verify the rail in the actual Payments contract
        Payments.RailView memory rail = payments.getRail(railId);
        
        assertEq(rail.token, address(mockUSDFC), "Token should be USDFC");
        assertEq(rail.from, client, "From address should be client");
        assertEq(rail.to, storageProvider, "To address should be storage provider");
        assertEq(rail.operator, address(pdpServiceWithPayments), "Operator should be the PDP service");
        assertEq(rail.arbiter, address(pdpServiceWithPayments), "Arbiter should be the PDP service");
        assertEq(rail.commissionRateBps, initialOperatorCommissionBps, "Commission rate should match the initial rate");
        
        // Verify lockupFixed is 0 since the one-time payment was made
        assertEq(rail.lockupFixed, 0, "Lockup fixed should be 0 after one-time payment");
        
        // Verify initial payment rate is 0 (will be updated when roots are added)
        assertEq(rail.paymentRate, 0, "Initial payment rate should be 0");
        
        // Get account balances after creating proof set
        (uint256 clientFundsAfter, ) = getAccountInfo(address(mockUSDFC), client);
        (uint256 spFundsAfter, ) = getAccountInfo(address(mockUSDFC), storageProvider);
        
        // Calculate expected client balance
        uint256 expectedClientFundsAfter = clientFundsBefore - pdpServiceWithPayments.PROOFSET_CREATION_FEE();
        
        // Verify balances changed correctly (one-time fee transferred)
        assertEq(clientFundsAfter, expectedClientFundsAfter, "Client funds should decrease by the proof set creation fee");
        assertTrue(spFundsAfter > spFundsBefore, "Storage provider funds should increase");
    }
    
    // Helper function to get account info from the Payments contract
    function getAccountInfo(address token, address owner) internal view returns (uint256 funds, uint256 lockupCurrent) {
        (funds, lockupCurrent, , ) = payments.accounts(token, owner);
        return (funds, lockupCurrent);
    }
    
    // Constants for calculations
    uint256 constant COMMISSION_MAX_BPS = 10000;
    
    function testGlobalParameters() public view {
        // These parameters should be the same as in SimplePDPService
        assertEq(pdpServiceWithPayments.getMaxProvingPeriod(), 2880, "Max proving period should be 2880 epochs");
        assertEq(pdpServiceWithPayments.challengeWindow(), 60, "Challenge window should be 60 epochs");
        assertEq(pdpServiceWithPayments.getChallengesPerProof(), 5, "Challenges per proof should be 5");
    }
}