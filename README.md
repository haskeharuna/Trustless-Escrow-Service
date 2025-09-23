# 🔐 Trustless Escrow Service

A smart contract-based escrow service built on Stacks blockchain using Clarity. This contract enables secure transactions between buyers and sellers with built-in dispute resolution mechanisms.

## 🚀 Features

- **💰 Secure Fund Holding**: Funds are held in the contract until both parties confirm service completion
- **🎯 Milestone Payments**: Break large projects into smaller, manageable payment stages
- **🤝 Two-Party Confirmation**: Both buyer and seller must confirm service delivery for fund release
- **⚖️ Dispute Resolution**: Built-in arbitration system for handling conflicts (per milestone or full escrow)
- **⏰ Emergency Cancellation**: Time-based emergency cancellation after dispute period
- **📊 Transparent Tracking**: Full visibility into escrow status and milestone progress

## 📋 Contract Functions

### 🎯 Milestone Escrow Functions

#### `create-milestone-escrow`
Creates a milestone-based escrow with multiple payment stages
```clarity
(create-milestone-escrow seller milestone-amounts milestone-descriptions)
```
- **seller**: Principal address of the service provider
- **milestone-amounts**: List of STX amounts for each milestone (in microSTX)
- **milestone-descriptions**: List of descriptions for each milestone (max 128 chars each)

#### `confirm-milestone`
Confirms completion of a specific milestone (called by buyer or seller)
```clarity
(confirm-milestone escrow-id milestone-index)
```
- **escrow-id**: Unique identifier of the escrow
- **milestone-index**: Index of the milestone to confirm (starts from 0)

#### `raise-milestone-dispute`
Raises a dispute for a specific milestone
```clarity
(raise-milestone-dispute escrow-id milestone-index arbiter)
```
- **escrow-id**: Unique identifier of the escrow
- **milestone-index**: Index of the disputed milestone
- **arbiter**: Principal address of the dispute resolver

#### `resolve-milestone-dispute`
Resolves a milestone dispute (called by arbiter only)
```clarity
(resolve-milestone-dispute escrow-id milestone-index award-to-seller)
```
- **escrow-id**: Unique identifier of the escrow
- **milestone-index**: Index of the disputed milestone
- **award-to-seller**: Boolean indicating if milestone funds should go to seller

#### `get-milestone`
Returns milestone details
```clarity
(get-milestone escrow-id milestone-index)
```

#### `get-milestone-count`
Returns number of milestones for an escrow
```clarity
(get-milestone-count escrow-id)
```

#### `get-releasable-amount`
Returns the total STX amount ready to be released (confirmed but not yet released)
```clarity
(get-releasable-amount escrow-id)
```

### Public Functions

#### `create-escrow`
Creates a new escrow agreement
```clarity
(create-escrow seller amount service-description)
```
- **seller**: Principal address of the service provider
- **amount**: STX amount to be held in escrow (in microSTX)
- **service-description**: Description of the service (max 256 characters)

#### `confirm-service`
Confirms service delivery (called by buyer or seller)
```clarity
(confirm-service escrow-id)
```
- **escrow-id**: Unique identifier of the escrow

#### `raise-dispute`
Raises a dispute and assigns an arbiter
```clarity
(raise-dispute escrow-id arbiter)
```
- **escrow-id**: Unique identifier of the escrow
- **arbiter**: Principal address of the dispute resolver

#### `resolve-dispute`
Resolves a dispute (called by arbiter only)
```clarity
(resolve-dispute escrow-id award-to-seller)
```
- **escrow-id**: Unique identifier of the escrow
- **award-to-seller**: Boolean indicating if funds should go to seller

#### `cancel-escrow`
Cancels an active escrow (buyer only)
```clarity
(cancel-escrow escrow-id)
```

#### `emergency-cancel`
Emergency cancellation after dispute period expires
```clarity
(emergency-cancel escrow-id)
```

### Read-Only Functions

#### `get-escrow`
Returns escrow details
```clarity
(get-escrow escrow-id)
```

#### `get-user-escrows`
Returns list of escrow IDs for a user
```clarity
(get-user-escrows user)
```

#### `get-escrow-balance`
Returns the STX balance held for an escrow
```clarity
(get-escrow-balance escrow-id)
```

## 🔄 Escrow Phases

1. **🟡 Active**: Escrow created, awaiting service delivery
2. **🟠 Confirming**: One party has confirmed, waiting for the other
3. **🟢 Completed**: Both parties confirmed, funds released to seller
4. **🔴 Disputed**: Dispute raised, awaiting arbitration
5. **⚫ Cancelled**: Escrow cancelled, funds returned to buyer

## 🛠️ Usage Examples

### Creating a Milestone Escrow
```clarity
;; Buyer creates milestone escrow for website development
;; 3 milestones: 300 STX (design), 400 STX (development), 300 STX (deployment)
(contract-call? .escrow create-milestone-escrow 
    'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 
    (list u300000000 u400000000 u300000000)
    (list "UI/UX Design" "Frontend Development" "Deployment & Testing")
)
```

### Confirming Milestone Completion
```clarity
;; Both buyer and seller confirm milestone 0 (design phase)
(contract-call? .escrow confirm-milestone u1 u0)
```

### Raising Milestone Dispute
```clarity
;; Buyer disputes milestone 1 (development phase)
(contract-call? .escrow raise-milestone-dispute u1 u1 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE)
```

### Creating an Escrow
```clarity
;; Buyer creates escrow for 1000 STX
(contract-call? .escrow create-escrow 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 1000000000 "Website development services")
```

### Confirming Service Delivery
```clarity
;; Both buyer and seller must call this
(contract-call? .escrow confirm-service u1)
```

### Raising a Dispute
```clarity
;; Either party can raise a dispute with an arbiter
(contract-call? .escrow raise-dispute u1 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE)
```

## 🔧 Development Setup

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Node.js and npm for testing

### Installation
```bash
git clone <repository-url>
cd trustless-escrow-service
clarinet check
```

### Running Tests
```bash
clarinet test
```

## 📝 Error Codes

- `u100`: Unauthorized operation
- `u101`: Escrow not found
- `u102`: Invalid amount
- `u103`: Escrow already exists
- `u104`: Wrong phase for operation
- `u105`: Not a participant in escrow
- `u106`: Already confirmed
- `u107`: Insufficient balance
- `u108`: Dispute period not passed
- `u109`: Already disputed
- `u110`: Milestone not found
- `u111`: Milestone already released
- `u112`: Invalid milestone data

## 🚧 Security Considerations

- All funds are held in the contract itself using `as-contract`
- Only participants can interact with their escrows
- Emergency cancellation requires dispute period to expire (144 blocks ≈ 24 hours)
- Arbiters can only act on disputed escrows assigned to them

## 📜 License

This project is open source and available under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
