//
//  LightningPeersViewController.swift
//  FullyNoded
//
//  Created by Peter on 17/08/20.
//  Copyright © 2020 Fontaine. All rights reserved.
//

import UIKit

class LightningPeersViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    var id = ""
    let spinner = ConnectingView()
    var peerArray = [[String:Any]]()
    var selectedPeer:[String:Any]?

    @IBOutlet weak var iconBackground: UIView!
    @IBOutlet weak var peersTable: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        peersTable.delegate = self
        peersTable.dataSource = self
        iconBackground.clipsToBounds = true
        iconBackground.layer.cornerRadius = 5
        loadPeers()
    }
    
    @IBAction func addPeerAction(_ sender: Any) {
        DispatchQueue.main.async { [weak self] in
            self?.performSegue(withIdentifier: "segueToAddPeer", sender: self)
        }
    }
    
    private func loadPeers() {
        spinner.addConnectingView(vc: self, description: "getting peers...")
        LightningRPC.command(method: .listpeers, param: "") { [weak self] (response, errorDesc) in
            if let dict = response as? NSDictionary {
                if let peers = dict["peers"] as? NSArray {
                    if peers.count > 0 {
                        self?.parsePeers(peers: peers)
                    } else {
                        self?.spinner.removeConnectingView()
                        showAlert(vc: self, title: "No peers yet", message: "Tap the + button to connect to a peer and start a channel")
                    }
                }
            } else {
                self?.spinner.removeConnectingView()
                showAlert(vc: self, title: "Error", message: errorDesc ?? "unknown error fetching peers")
            }
        }
    }
    
    private func parsePeers(peers: NSArray) {
        for (i, peer) in peers.enumerated() {
            if let peerDict = peer as? [String:Any] {
                peerArray.append(peerDict)
            }
            if i + 1 == peers.count {
                DispatchQueue.main.async { [unowned vc = self] in
                    vc.peersTable.reloadData()
                    vc.spinner.removeConnectingView()
                }
            }
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return peerArray.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "peerCell", for: indexPath)
        cell.selectionStyle = .none
        cell.layer.borderColor = UIColor.lightGray.cgColor
        cell.layer.borderWidth = 0.5
        let connectedImageView = cell.viewWithTag(1) as! UIImageView
        let idLabel = cell.viewWithTag(2) as! UILabel
        let channelsImageView = cell.viewWithTag(3) as! UIImageView
        let channelStatus = cell.viewWithTag(4) as! UILabel
        
        if peerArray.count > 0 {
            let dict = peerArray[indexPath.section]
            
            if let id = dict["id"] as? String {
                idLabel.text = id
            }
            
            if let connected = dict["connected"] as? Bool {
                if connected {
                    connectedImageView.image = UIImage(systemName: "person.crop.circle.badge.checkmark")
                    connectedImageView.tintColor = .systemGreen
                } else {
                    connectedImageView.image = UIImage(systemName: "person.crop.circle.badge.exclam")
                    connectedImageView.tintColor = .systemRed
                }
            }
            
            if let channels = dict["channels"] as? NSArray {
                if channels.count > 0 {
                    channelsImageView.image = UIImage(systemName: "bolt")
                    channelsImageView.tintColor = .systemYellow
                    if let status = (channels[0] as! NSDictionary)["state"] as? String {
                        channelStatus.text = status
                    } else {
                        channelStatus.text = ""
                    }
                } else {
                    channelsImageView.image = UIImage(systemName: "bolt.slash")
                    channelsImageView.tintColor = .systemBlue
                    channelStatus.text = "no channels with peer"
                }
            }
            
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        DispatchQueue.main.async { [weak self] in
            self?.id = self?.peerArray[indexPath.section]["id"] as? String ?? ""
            self?.performSegue(withIdentifier: "segueToKeySend", sender: self)
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 96
    }
    
    private func addPeer(id: String, ip: String, port: String?) {
        spinner.addConnectingView(vc: self, description: "connecting peer...")
        let param = "\(id)@\(ip):\(port ?? "9735")"
        LightningRPC.command(method: .connect, param: "\(param)") { [weak self] (response, errorDesc) in
            if let dict = response as? NSDictionary {
                self?.spinner.removeConnectingView()
                if let id = dict["id"] as? String {
                    showAlert(vc: self, title: "Success ✅", message: "⚡️ peer added with id: \(id)")
                } else {
                    showAlert(vc: self, title: "Something is not quite right", message: "This is the response we got: \(dict)")
                }
                self?.loadPeers()
            } else {
                self?.spinner.removeConnectingView()
                showAlert(vc: self, title: "Error", message: errorDesc ?? "error adding peer")
            }
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller
        
        if segue.identifier == "segueToKeySend" {
            if let vc = segue.destination as? KeySendViewController {
                vc.id = id
            }
        }
        
        if segue.identifier == "segueToPeerDetails" {
            if let vc = segue.destination as? ProcessPSBTViewController {
                vc.showPeer = true
                if selectedPeer != nil {
                    vc.peer = selectedPeer
                }
            }
        }
        
        if segue.identifier == "segueToAddPeer" {
            if let vc = segue.destination as? QRScannerViewController {
                vc.isScanningAddress = true
                vc.onAddressDoneBlock = { url in
                    if url != nil {
                        let arr = url!.split(separator: "@")
                        if arr.count > 0 {
                            let arr1 = "\(arr[1])".split(separator: ":")
                            let id = "\(arr[0])"
                            let ip = "\(arr1[0])"
                            if arr1.count > 0 {
                                let port = "\(arr1[1])"
                                self.addPeer(id: id, ip: ip, port: port)
                            }
                        }
                    }
                }
            }
        }
    }

}
