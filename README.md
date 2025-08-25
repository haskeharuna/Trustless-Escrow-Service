# 🔐 Trustless Escrow Service

A smart contract-based escrow service built on Stacks blockchain using Clarity. This contract enables secure transactions between buyers and sellers with built-in dispute resolution mechanisms.

## 🚀 Features

- **💰 Secure Fund Holding**: Funds are held in the contract until both parties confirm service completion
- **🤝 Two-Party Confirmation**: Both buyer and seller must confirm service delivery for fund release
- **⚖️ Dispute Resolution**: Built-in arbitration system for handling conflicts
- **⏰ Emergency Cancellation**: Time-based emergency cancellation after dispute period
- **📊 Transparent Tracking**: Full visibility into escrow status and history

## 📋 Contract Functions

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

## 🚧 Security Considerations

- All funds are held in the contract itself using `as-contract`
- Only participants can interact with their escrows
- Emergency cancellation requires dispute period to expire (144 blocks ≈ 24 hours)
- Arbiters can only act on disputed escrows assigned to them

## 📜 License

This project is open source and available under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
