//
//  InvoiceViewController.swift
//  BitSense
//
//  Created by Peter on 21/03/19.
//  Copyright © 2019 Fontaine. All rights reserved.
//

import UIKit

class InvoiceViewController: UIViewController, UITextFieldDelegate {
    
    @IBOutlet weak var segmentedControlOutlet: UISegmentedControl!
    var textToShareViaQRCode = String()
    var addressString = String()
    var qrCode = UIImage()
    let descriptionLabel = UILabel()
    var tapQRGesture = UITapGestureRecognizer()
    var tapAddressGesture = UITapGestureRecognizer()
    var nativeSegwit = Bool()
    var p2shSegwit = Bool()
    var legacy = Bool()
    let spinner = ConnectingView()
    let qrGenerator = QRGenerator()
    var isHDMusig = Bool()
    var isHDInvoice = Bool()
    let cd = CoreDataService()
    var descriptor = ""
    var wallet = [String:Any]()
    let ud = UserDefaults.standard
    
    @IBOutlet var amountField: UITextField!
    @IBOutlet var labelField: UITextField!
    @IBOutlet var qrView: UIImageView!
    @IBOutlet var addressOutlet: UILabel!
    @IBOutlet var minusOutlet: UIButton!
    @IBOutlet var plusOutlet: UIButton!
    @IBOutlet var indexDisplay: UILabel!
    @IBOutlet var indexLabel: UILabel!
    var isBtc = false
    var isSats = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        spinner.addConnectingView(vc: self, description: "fetching address...")
        addressOutlet.isUserInteractionEnabled = true
        addressOutlet.text = ""
        minusOutlet.alpha = 0
        plusOutlet.alpha = 0
        indexLabel.alpha = 0
        indexDisplay.alpha = 0
        amountField.delegate = self
        labelField.delegate = self
        amountField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        labelField.addTarget(self, action: #selector(textFieldDidChange(_:)), for: .editingChanged)
        let tap: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tap)
        getAddressSettings()
        addDoneButtonOnKeyboard()
        load()
        if ud.object(forKey: "invoiceUnit") != nil {
            let unit = ud.object(forKey: "invoiceUnit") as! String
            if unit == "btc" {
                segmentedControlOutlet.selectedSegmentIndex = 0
                isBtc = true
                isSats = false
            } else {
                segmentedControlOutlet.selectedSegmentIndex = 1
                isSats = true
                isBtc = false
            }
        } else {
            segmentedControlOutlet.selectedSegmentIndex = 0
        }
    }
    
    @IBAction func denominationChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            ud.set("btc", forKey: "invoiceUnit")
            isBtc = true
            isSats = false
        case 1:
            ud.set("sats", forKey: "invoiceUnit")
            isSats = true
            isBtc = false
        default:
            break
        }
    }
    
    
    @IBAction func lightningInvoice(_ sender: Any) {
        spinner.addConnectingView(vc: self, description: "creating lightning invoice...")
        // invoice msatoshi label description
        var millisats = "\"any\""
        var label = "Fully-Noded-\(randomString(length: 5))"
        if amountField.text != "" {
            if isBtc {
                if let dbl = Double(amountField.text!) {
                    let int = Int(dbl * 100000000000.0)
                    millisats = "\(int)"
                }
            } else if isSats {
                if let int = Double(amountField.text!) {
                    millisats = "\(Int(int * 1000))"
                }
            }
        }
        if labelField.text != "" {
            label = labelField.text!
        }
        let param = "\(millisats), \"\(label)\", \"\(Date())\", \(86400)"
        LightningRPC.command(method: .invoice, param: param) { [weak self] (response, errorDesc) in
            if let dict = response as? NSDictionary {
                if let bolt11 = dict["bolt11"] as? String {
                    DispatchQueue.main.async { [weak self] in
                        self?.addressOutlet.alpha = 1
                        self?.addressString = bolt11
                        self?.addressOutlet.text = bolt11
                        self?.showAddress(address: bolt11)
                        self?.spinner.removeConnectingView()
                    }
                }
                if let warning = dict["warning_capacity"] as? String {
                    if warning != "" {
                        showAlert(vc: self, title: "Warning", message: warning)
                    }
                }
            } else {
                self?.spinner.removeConnectingView()
                showAlert(vc: self, title: "Error", message: errorDesc ?? "we had an issue getting your lightning invoice")
            }
        }
    }
    
    
    @IBAction func minusAction(_ sender: Any) {
        if indexDisplay.text != "" {
            let index = Int(indexDisplay.text!)!
            if index != 0 {
                //fetch new address then save the updated index
                spinner.addConnectingView(vc: self, description: "fetching address index \(index - 1)")
                DispatchQueue.main.async {
                    self.indexDisplay.text = "\(index - 1)"
                }
                let param = "\(descriptor), [\(index - 1),\(index - 1)]"
                self.executeNodeCommand(method: .deriveaddresses, param: param)
            }
        }
    }
    
    @IBAction func plusAction(_ sender: Any) {
        if indexDisplay.text != "" {
            let index = Int(indexDisplay.text!)!
            if index >= 0 {
                //fetch new address then save the updated index
                spinner.addConnectingView(vc: self, description: "fetching address index \(index + 1)")
                DispatchQueue.main.async {
                    self.indexDisplay.text = "\(index + 1)"
                }
                let param = "\(descriptor), [\(index + 1),\(index + 1)]"
                self.executeNodeCommand(method: .deriveaddresses, param: param)
            }
        }
    }
    
    func load() {
        addressOutlet.text = ""
        if isHDInvoice {
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.2, animations: {
                    self.minusOutlet.alpha = 1
                    self.plusOutlet.alpha = 1
                    self.indexLabel.alpha = 1
                    self.indexDisplay.alpha = 1
                }) { _ in
                    self.getHDMusigAddress()
                }
            }
        } else {
            activeWallet { [weak self] (wallet) in
                if wallet != nil {
                    let descriptorParser = DescriptorParser()
                    let descriptorStruct = descriptorParser.descriptor(wallet!.receiveDescriptor)
                    if descriptorStruct.isMulti {
                        self?.getReceieveAddressForFullyNodedMultiSig(wallet!)
                    } else {
                        self?.showAddress()
                    }
                } else {
                    self?.showAddress()
                }
            }
        }
    }
    
    private func getReceieveAddressForFullyNodedMultiSig(_ wallet: Wallet) {
        let index = Int(wallet.index) + 1
        CoreDataService.update(id: wallet.id, keyToUpdate: "index", newValue: Int64(index), entity: .wallets) { (success) in
            if success {
                let param = "\"\(wallet.receiveDescriptor)\", [\(index),\(index)]"
                Reducer.makeCommand(command: .deriveaddresses, param: param) { (response, errorMessage) in
                    if let addresses = response as? NSArray {
                        if let address = addresses[0] as? String {
                            DispatchQueue.main.async { [weak self] in
                                self?.addressOutlet.alpha = 1
                                self?.addressString = address
                                self?.addressOutlet.text = address
                                self?.showAddress(address: address)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @IBAction func getAddressInfo(_ sender: Any) {
        DispatchQueue.main.async { [weak self] in
            self?.performSegue(withIdentifier: "getAddressInfo", sender: self)
        }
    }
    
    func getHDMusigAddress() {
        let walletStr = WalletOld(dictionary: wallet)
        Crypto.decryptData(dataToDecrypt: walletStr.descriptor!) { [weak self] (desc) in
            if desc != nil {
                self?.descriptor = desc!.utf8
                let label = walletStr.label
                let addressIndex = "\(walletStr.index)"
                let param = "\(self?.descriptor), [\(addressIndex),\(addressIndex)]"
                Reducer.makeCommand(command: .deriveaddresses, param: param) { (response, errorMessage) in
                    if let result = response as? NSArray {
                        if let addressToReturn = result[0] as? String {
                            DispatchQueue.main.async { [weak self] in
                                self?.indexDisplay.text = addressIndex
                                self?.addressOutlet.text = addressToReturn
                                self?.navigationController?.navigationBar.topItem?.title = label
                                self?.addressString = addressToReturn
                                self?.isHDMusig = true
                                self?.showAddress()
                            }
                        }
                    } else {
                        self?.spinner.removeConnectingView()
                        displayAlert(viewController: self, isError: true, message: errorMessage ?? "error deriving addresses")
                    }
                }
            }
        }
    }
    
    func getAddressSettings() {
        let ud = UserDefaults.standard
        nativeSegwit = ud.object(forKey: "nativeSegwit") as? Bool ?? true
        p2shSegwit = ud.object(forKey: "p2shSegwit") as? Bool ?? false
        legacy = ud.object(forKey: "legacy") as? Bool ?? false
    }
    
    func showAddress() {
        if isHDMusig {
            showAddress(address: addressString)
            spinner.removeConnectingView()
            DispatchQueue.main.async { [weak self] in
                self?.addressOutlet.text = self?.addressString
            }
        } else {
            var params = ""
            if self.nativeSegwit {
                params = "\"\", \"bech32\""
            } else if self.legacy {
                params = "\"\", \"legacy\""
            } else if self.p2shSegwit {
                params = "\"\", \"p2sh-segwit\""
            }
            self.executeNodeCommand(method: .getnewaddress, param: params)
        }
    }
    
    func showAddress(address: String) {
        DispatchQueue.main.async { [weak self] in
            if self != nil {
                self!.qrCode = self!.generateQrCode(key: address)
                self!.qrView.image = self?.qrCode
                self!.qrView.isUserInteractionEnabled = true
                self!.qrView.alpha = 0
                self!.view.addSubview(self!.qrView)
                self!.descriptionLabel.frame = CGRect(x: 10, y: self!.view.frame.maxY - 30, width: self!.view.frame.width - 20, height: 20)
                self!.descriptionLabel.textAlignment = .center
                self!.descriptionLabel.font = UIFont.init(name: "HelveticaNeue-Light", size: 12)
                self!.descriptionLabel.textColor = UIColor.white
                self!.descriptionLabel.text = "Tap the QR Code or text to copy/save/share"
                self!.descriptionLabel.adjustsFontSizeToFitWidth = true
                self!.descriptionLabel.alpha = 0
                self!.view.addSubview(self!.descriptionLabel)
                self!.tapAddressGesture = UITapGestureRecognizer(target: self!, action: #selector(self!.shareAddressText(_:)))
                self!.addressOutlet.addGestureRecognizer(self!.tapAddressGesture)
                self!.addressOutlet.text = address
                self!.addressString = address
                self!.tapQRGesture = UITapGestureRecognizer(target: self!, action: #selector(self?.shareQRCode(_:)))
                self!.qrView.addGestureRecognizer(self!.tapQRGesture)
                self!.spinner.removeConnectingView()
                UIView.animate(withDuration: 0.3, animations: { [weak self] in
                    self?.descriptionLabel.alpha = 1
                    self?.qrView.alpha = 1
                    self?.addressOutlet.alpha = 1
                })
            }
        }
    }
    
    
    @objc func shareAddressText(_ sender: UITapGestureRecognizer) {
        
        UIView.animate(withDuration: 0.2, animations: {
            
            self.addressOutlet.alpha = 0
            
        }) { _ in
            
            UIView.animate(withDuration: 0.2, animations: {
                
                self.addressOutlet.alpha = 1
                
            })
            
        }
        
        DispatchQueue.main.async {
            
            let textToShare = [self.addressString]
            
            let activityViewController = UIActivityViewController(activityItems: textToShare,
                                                                  applicationActivities: nil)
            
            activityViewController.popoverPresentationController?.sourceView = self.view
            self.present(activityViewController, animated: true) {}
            
        }
        
    }
    
    @objc func shareQRCode(_ sender: UITapGestureRecognizer) {
        
        UIView.animate(withDuration: 0.2, animations: {
            
            self.qrView.alpha = 0
            
        }) { _ in
            
            UIView.animate(withDuration: 0.2, animations: {
                
                self.qrView.alpha = 1
                
            }) { _ in
                
                let activityController = UIActivityViewController(activityItems: [self.qrView.image!],
                                                                  applicationActivities: nil)
                
                activityController.popoverPresentationController?.sourceView = self.view
                self.present(activityController, animated: true) {}
                
            }
            
        }
        
    }
    
    func executeNodeCommand(method: BTC_CLI_COMMAND, param: String) {
        print("executeNodeCommand")
        
        func deriveAddresses() {
            Reducer.makeCommand(command: .deriveaddresses, param: param) { [weak self] (response, errorMessage) in
                if let result = response as? NSArray {
                    if let addressToReturn = result[0] as? String {
                        DispatchQueue.main.async { [weak self] in
                            self?.spinner.removeConnectingView()
                            self?.addressString = addressToReturn
                            self?.addressOutlet.text = addressToReturn
                            self?.showAddress(address: addressToReturn)
                            let id = self?.wallet["id"] as! UUID
                            if self != nil {
                                if self?.indexDisplay.text != nil {
                                    CoreDataService.update(id: id, keyToUpdate: "index", newValue: Int32(self!.indexDisplay.text!)!, entity: .newHdWallets) { success in
                                        if success {
                                            print("updated index")
                                        } else {
                                            print("index update failed")
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    self?.spinner.removeConnectingView()
                    displayAlert(viewController: self, isError: true, message: errorMessage ?? "error deriving addresses")
                }
            }
        }
        
        func getAddress() {
            Reducer.makeCommand(command: .getnewaddress, param: param) { [weak self] (response, errorMessage) in
                if let address = response as? String {
                    DispatchQueue.main.async { [weak self] in
                        self?.spinner.removeConnectingView()
                        self?.addressString = address
                        self?.addressOutlet.text = address
                        self?.showAddress(address: address)
                    }
                } else {
                    if self != nil {
                        self!.spinner.removeConnectingView()
                        showAlert(vc: self!, title: "Error", message: errorMessage ?? "error fecthing address")
                    }
                }
            }
        }
        
        switch method {
        case .deriveaddresses:
            deriveAddresses()
            
        case .getnewaddress:
            getAddress()
            
        default:
            break
        }
    }
    
    @objc func textFieldDidChange(_ textField: UITextField) {
        print("textFieldDidChange")
        
        updateQRImage()
        
    }
    
    func generateQrCode(key: String) -> UIImage {
        
        qrGenerator.textInput = key
        let qr = qrGenerator.getQRCode()
        
        return qr
        
    }
    
    func updateQRImage() {
        var newImage = UIImage()
        var amount = self.amountField.text ?? ""
        if isSats {
            if amount != "" {
                if let int = Int(amount) {
                    amount = "\(Double(int) * 100000000.0)"
                }
            }
        }
        if !addressString.hasPrefix("lntb") && !addressString.hasPrefix("lightning:") && !addressString.hasPrefix("lnbc") && !addressString.hasPrefix("lnbcrt") {
            if self.amountField.text == "" && self.labelField.text == "" {
                newImage = self.generateQrCode(key:"bitcoin:\(self.addressString)")
                textToShareViaQRCode = "bitcoin:\(self.addressString)"
                
            } else if self.amountField.text != "" && self.labelField.text != "" {
                newImage = self.generateQrCode(key:"bitcoin:\(self.addressString)?amount=\(amount)&label=\(self.labelField.text!)")
                textToShareViaQRCode = "bitcoin:\(self.addressString)?amount=\(self.amountField.text!)&label=\(self.labelField.text!)"
                
            } else if self.amountField.text != "" && self.labelField.text == "" {
                newImage = self.generateQrCode(key:"bitcoin:\(self.addressString)?amount=\(amount)")
                textToShareViaQRCode = "bitcoin:\(self.addressString)?amount=\(self.amountField.text!)"
                
            } else if self.amountField.text == "" && self.labelField.text != "" {
                newImage = self.generateQrCode(key:"bitcoin:\(self.addressString)?label=\(self.labelField.text!)")
                textToShareViaQRCode = "bitcoin:\(self.addressString)?label=\(self.labelField.text!)"
                
            }
            
            DispatchQueue.main.async {
                UIView.transition(with: self.qrView,
                                  duration: 0.75,
                                  options: .transitionCrossDissolve,
                                  animations: { self.qrView.image = newImage },
                                  completion: nil)
            }
        }
    }
    
    @objc func doneButtonAction() {
        
        self.amountField.resignFirstResponder()
        
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        view.endEditing(true)
        return false
        
    }
    
    func addDoneButtonOnKeyboard() {
        
        let doneToolbar = UIToolbar()
        
        doneToolbar.frame = CGRect(x: 0,
                                   y: 0,
                                   width: 320,
                                   height: 50)
        
        doneToolbar.barStyle = UIBarStyle.default
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.flexibleSpace,
                                        target: nil,
                                        action: nil)
        
        let done: UIBarButtonItem = UIBarButtonItem(title: "Done",
                                                    style: UIBarButtonItem.Style.done,
                                                    target: self,
                                                    action: #selector(doneButtonAction))
        
        let items = NSMutableArray()
        items.add(flexSpace)
        items.add(done)
        
        doneToolbar.items = (items as! [UIBarButtonItem])
        doneToolbar.sizeToFit()
        
        self.amountField.inputAccessoryView = doneToolbar
        
    }
    
    @objc func dismissKeyboard() {
        
        view.endEditing(true)
        
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "getAddressInfo" {
            
            if let vc = segue.destination as? GetInfoViewController {
                
                vc.address = addressString
                vc.getAddressInfo = true
                
            }
            
        }
        
    }

}
