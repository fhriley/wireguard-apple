// SPDX-License-Identifier: MIT
// Copyright © 2018 WireGuard LLC. All Rights Reserved.

import UIKit
import MobileCoreServices

class TunnelsListTableViewController: UIViewController {

    var tunnelsManager: TunnelsManager?
    var onTunnelsManagerReady: ((TunnelsManager) -> Void)?

    var busyIndicator: UIActivityIndicatorView?
    var centeredAddButton: BorderedTextButton?
    var tableView: UITableView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.white

        // Set up the navigation bar
        self.title = "WireGuard"
        let addButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addButtonTapped(sender:)))
        self.navigationItem.rightBarButtonItem = addButtonItem
        let settingsButtonItem = UIBarButtonItem(title: "Settings", style: .plain, target: self, action: #selector(settingsButtonTapped(sender:)))
        self.navigationItem.leftBarButtonItem = settingsButtonItem

        // Set up the busy indicator
        let busyIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
        busyIndicator.hidesWhenStopped = true

        // Add the busyIndicator, centered
        view.addSubview(busyIndicator)
        busyIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            busyIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            busyIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        busyIndicator.startAnimating()
        self.busyIndicator = busyIndicator

        // Create the tunnels manager, and when it's ready, create the tableView
        TunnelsManager.create { [weak self] tunnelsManager in
            guard let tunnelsManager = tunnelsManager else { return }
            guard let s = self else { return }

            let tableView = UITableView(frame: CGRect.zero, style: .plain)
            tableView.rowHeight = 60
            tableView.separatorStyle = .none
            tableView.register(TunnelsListTableViewCell.self, forCellReuseIdentifier: TunnelsListTableViewCell.id)

            s.view.addSubview(tableView)
            tableView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tableView.leftAnchor.constraint(equalTo: s.view.leftAnchor),
                tableView.rightAnchor.constraint(equalTo: s.view.rightAnchor),
                tableView.topAnchor.constraint(equalTo: s.view.topAnchor),
                tableView.bottomAnchor.constraint(equalTo: s.view.bottomAnchor)
                ])
            tableView.dataSource = s
            tableView.delegate = s
            s.tableView = tableView

            // Add an add button, centered
            let centeredAddButton = BorderedTextButton()
            centeredAddButton.title = "Add a tunnel"
            centeredAddButton.isHidden = true
            s.view.addSubview(centeredAddButton)
            centeredAddButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                centeredAddButton.centerXAnchor.constraint(equalTo: s.view.centerXAnchor),
                centeredAddButton.centerYAnchor.constraint(equalTo: s.view.centerYAnchor)
                ])
            centeredAddButton.onTapped = { [weak self] in
                self?.addButtonTapped(sender: centeredAddButton)
            }
            s.centeredAddButton = centeredAddButton

            centeredAddButton.isHidden = (tunnelsManager.numberOfTunnels() > 0)
            busyIndicator.stopAnimating()

            tunnelsManager.delegate = s
            s.tunnelsManager = tunnelsManager
            s.onTunnelsManagerReady?(tunnelsManager)
            s.onTunnelsManagerReady = nil
        }
    }

    @objc func addButtonTapped(sender: AnyObject) {
        if (self.tunnelsManager == nil) { return } // Do nothing until we've loaded the tunnels
        let alert = UIAlertController(title: "", message: "Add a new WireGuard tunnel", preferredStyle: .actionSheet)
        let importFileAction = UIAlertAction(title: "Create from file or archive", style: .default) { [weak self] (_) in
            self?.presentViewControllerForFileImport()
        }
        alert.addAction(importFileAction)

        let scanQRCodeAction = UIAlertAction(title: "Create from QR code", style: .default) { [weak self] (_) in
            self?.presentViewControllerForScanningQRCode()
        }
        alert.addAction(scanQRCodeAction)

        let createFromScratchAction = UIAlertAction(title: "Create from scratch", style: .default) { [weak self] (_) in
            if let s = self, let tunnelsManager = s.tunnelsManager {
                s.presentViewControllerForTunnelCreation(tunnelsManager: tunnelsManager, tunnelConfiguration: nil)
            }
        }
        alert.addAction(createFromScratchAction)

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
        alert.addAction(cancelAction)

        // popoverPresentationController will be nil on iPhone and non-nil on iPad
        if let sender = sender as? UIBarButtonItem {
            alert.popoverPresentationController?.barButtonItem = sender
        } else if let sender = sender as? UIView {
            alert.popoverPresentationController?.sourceView = sender
        }
        self.present(alert, animated: true, completion: nil)
    }

    @objc func settingsButtonTapped(sender: UIBarButtonItem!) {
        if (self.tunnelsManager == nil) { return } // Do nothing until we've loaded the tunnels
        let settingsVC = SettingsTableViewController(tunnelsManager: tunnelsManager)
        let settingsNC = UINavigationController(rootViewController: settingsVC)
        settingsNC.modalPresentationStyle = .formSheet
        self.present(settingsNC, animated: true)
    }

    func openForEditing(configFileURL: URL) {
        let tunnelConfiguration: TunnelConfiguration?
        let name = configFileURL.deletingPathExtension().lastPathComponent
        do {
            let fileContents = try String(contentsOf: configFileURL)
            try tunnelConfiguration = WgQuickConfigFileParser.parse(fileContents, name: name)
        } catch (let error) {
            showErrorAlert(title: "Unable to import tunnel", message: "An error occured when importing the tunnel configuration: \(String(describing: error))")
            return
        }
        tunnelConfiguration?.interface.name = name
        if let tunnelsManager = tunnelsManager {
            presentViewControllerForTunnelCreation(tunnelsManager: tunnelsManager, tunnelConfiguration: tunnelConfiguration)
        } else {
            onTunnelsManagerReady = { [weak self] tunnelsManager in
                self?.presentViewControllerForTunnelCreation(tunnelsManager: tunnelsManager, tunnelConfiguration: tunnelConfiguration)
            }
        }
    }

    func presentViewControllerForTunnelCreation(tunnelsManager: TunnelsManager, tunnelConfiguration: TunnelConfiguration?) {
        let editVC = TunnelEditTableViewController(tunnelsManager: tunnelsManager, tunnelConfiguration: tunnelConfiguration)
        let editNC = UINavigationController(rootViewController: editVC)
        editNC.modalPresentationStyle = .formSheet
        self.present(editNC, animated: true)
    }

    func presentViewControllerForFileImport() {
        let documentTypes = ["com.wireguard.config.quick", String(kUTTypeZipArchive)]
        let filePicker = UIDocumentPickerViewController(documentTypes: documentTypes, in: .import)
        filePicker.delegate = self
        self.present(filePicker, animated: true)
    }

    func presentViewControllerForScanningQRCode() {
        let scanQRCodeVC = QRScanViewController()
        scanQRCodeVC.delegate = self
        let scanQRCodeNC = UINavigationController(rootViewController: scanQRCodeVC)
        scanQRCodeNC.modalPresentationStyle = .fullScreen
        self.present(scanQRCodeNC, animated: true)
    }

    func showErrorAlert(title: String, message: String) {
        let okAction = UIAlertAction(title: "OK", style: .default)
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(okAction)

        self.present(alert, animated: true, completion: nil)
    }

    func importFromFile(url: URL) {
        // Import configurations from a .conf or a .zip file
        if (url.pathExtension == "conf") {
            let fileBaseName = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            if let fileContents = try? String(contentsOf: url),
                let tunnelConfiguration = try? WgQuickConfigFileParser.parse(fileContents, name: fileBaseName) {
                tunnelsManager?.add(tunnelConfiguration: tunnelConfiguration) { (_, error) in
                    if let error = error {
                        ErrorPresenter.showErrorAlert(error: error, from: self)
                    }
                }
            } else {
                showErrorAlert(title: "Unable to import tunnel", message: "An error occured when importing the tunnel configuration.")
            }
        } else if (url.pathExtension == "zip") {
            var unarchivedFiles: [(fileName: String, contents: Data)] = []
            do {
                unarchivedFiles = try ZipArchive.unarchive(url: url, requiredFileExtensions: ["conf"])
            } catch ZipArchiveError.cantOpenInputZipFile {
                showErrorAlert(title: "Unable to read zip archive", message: "The zip archive could not be read.")
                return
            } catch ZipArchiveError.badArchive {
                showErrorAlert(title: "Unable to read zip archive", message: "Bad or corrupt zip archive.")
                return
            } catch (let error) {
                showErrorAlert(title: "Unable to read zip archive", message: "Unexpected error: \(String(describing: error))")
                return
            }

            for (i, unarchivedFile) in unarchivedFiles.enumerated().reversed() {
                let fileBaseName = URL(string: unarchivedFile.fileName)?.deletingPathExtension().lastPathComponent
                if let trimmedName = fileBaseName?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedName.isEmpty {
                    unarchivedFiles[i].fileName = trimmedName
                } else {
                    unarchivedFiles.remove(at: i)
                }
            }
            if (unarchivedFiles.isEmpty) {
                showErrorAlert(title: "No tunnels in zip archive", message: "No .conf tunnel files were found inside the zip archive.")
                return
            }
            guard let tunnelsManager = tunnelsManager else { return }
            unarchivedFiles.sort { $0.fileName < $1.fileName }
            var lastFileName: String?
            var configs: [TunnelConfiguration] = []
            for file in unarchivedFiles {
                if file.fileName == lastFileName {
                    continue
                }
                lastFileName = file.fileName
                guard let fileContents = String(data: file.contents, encoding: .utf8) else {
                    continue
                }
                guard let tunnelConfig = try? WgQuickConfigFileParser.parse(fileContents, name: file.fileName) else {
                    continue
                }
                configs.append(tunnelConfig)
            }
            tunnelsManager.addMultiple(tunnelConfigurations: configs) { [weak self] (numberSuccessful) in
                if numberSuccessful == unarchivedFiles.count {
                    return
                }
                self?.showErrorAlert(title: "Created \(numberSuccessful) tunnels",
                    message: "Created \(numberSuccessful) of \(unarchivedFiles.count) tunnels from zip archive")
            }
        }
    }
}

// MARK: UIDocumentPickerDelegate

extension TunnelsListTableViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            importFromFile(url: url)
        }
    }
}

// MARK: QRScanViewControllerDelegate

extension TunnelsListTableViewController: QRScanViewControllerDelegate {
    func addScannedQRCode(tunnelConfiguration: TunnelConfiguration, qrScanViewController: QRScanViewController,
                       completionHandler: (() -> Void)?) {
        tunnelsManager?.add(tunnelConfiguration: tunnelConfiguration) { (_, error) in
            if let error = error {
                ErrorPresenter.showErrorAlert(error: error, from: qrScanViewController, onDismissal: completionHandler)
            } else {
                completionHandler?()
            }
        }
    }
}

// MARK: UITableViewDataSource

extension TunnelsListTableViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (tunnelsManager?.numberOfTunnels() ?? 0)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TunnelsListTableViewCell.id, for: indexPath) as! TunnelsListTableViewCell
        if let tunnelsManager = tunnelsManager {
            let tunnel = tunnelsManager.tunnel(at: indexPath.row)
            cell.tunnel = tunnel
            cell.onSwitchToggled = { [weak self] isOn in
                guard let s = self, let tunnelsManager = s.tunnelsManager else { return }
                if (isOn) {
                    tunnelsManager.startActivation(of: tunnel) { [weak s] error in
                        if let error = error {
                            ErrorPresenter.showErrorAlert(error: error, from: s, onPresented: {
                                DispatchQueue.main.async {
                                    cell.statusSwitch.isOn = false
                                }
                            })
                        }
                    }
                } else {
                    tunnelsManager.startDeactivation(of: tunnel) { [weak s] error in
                        s?.showErrorAlert(title: "Deactivation error", message: "Error while bringing down tunnel: \(String(describing: error))")
                    }
                }
            }
        }
        return cell
    }
}

// MARK: UITableViewDelegate

extension TunnelsListTableViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let tunnelsManager = tunnelsManager else { return }
        let tunnel = tunnelsManager.tunnel(at: indexPath.row)
        let tunnelDetailVC = TunnelDetailTableViewController(tunnelsManager: tunnelsManager,
                                                             tunnel: tunnel)
        let tunnelDetailNC = UINavigationController(rootViewController: tunnelDetailVC)
        showDetailViewController(tunnelDetailNC, sender: self) // Shall get propagated up to the split-vc
    }

    func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete", handler: { [weak self] (_, _, completionHandler) in
            guard let tunnelsManager = self?.tunnelsManager else { return }
            let tunnel = tunnelsManager.tunnel(at: indexPath.row)
            tunnelsManager.remove(tunnel: tunnel, completionHandler: { (error) in
                if (error != nil) {
                    ErrorPresenter.showErrorAlert(error: error!, from: self)
                    completionHandler(false)
                } else {
                    completionHandler(true)
                }
            })
        })
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

// MARK: TunnelsManagerDelegate

extension TunnelsListTableViewController: TunnelsManagerDelegate {
    func tunnelAdded(at index: Int) {
        tableView?.insertRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
        centeredAddButton?.isHidden = (tunnelsManager?.numberOfTunnels() ?? 0 > 0)
    }

    func tunnelModified(at index: Int) {
        tableView?.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
    }

    func tunnelMoved(at oldIndex: Int, to newIndex: Int) {
        tableView?.moveRow(at: IndexPath(row: oldIndex, section: 0), to: IndexPath(row: newIndex, section: 0))
    }

    func tunnelRemoved(at index: Int) {
        tableView?.deleteRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
        centeredAddButton?.isHidden = (tunnelsManager?.numberOfTunnels() ?? 0 > 0)
    }
}

class TunnelsListTableViewCell: UITableViewCell {
    static let id: String = "TunnelsListTableViewCell"
    var tunnel: TunnelContainer? {
        didSet(value) {
            // Bind to the tunnel's name
            nameLabel.text = tunnel?.name ?? ""
            nameObservervationToken = tunnel?.observe(\.name) { [weak self] (tunnel, _) in
                self?.nameLabel.text = tunnel.name
            }
            // Bind to the tunnel's status
            update(from: tunnel?.status)
            statusObservervationToken = tunnel?.observe(\.status) { [weak self] (tunnel, _) in
                self?.update(from: tunnel.status)
            }
        }
    }
    var onSwitchToggled: ((Bool) -> Void)?

    let nameLabel: UILabel
    let busyIndicator: UIActivityIndicatorView
    let statusSwitch: UISwitch

    private var statusObservervationToken: AnyObject?
    private var nameObservervationToken: AnyObject?

    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
        nameLabel = UILabel()
        busyIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
        busyIndicator.hidesWhenStopped = true
        statusSwitch = UISwitch()
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(statusSwitch)
        statusSwitch.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusSwitch.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusSwitch.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -8)
            ])
        contentView.addSubview(busyIndicator)
        busyIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            busyIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            busyIndicator.rightAnchor.constraint(equalTo: statusSwitch.leftAnchor, constant: -8)
            ])
        contentView.addSubview(nameLabel)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 16),
            nameLabel.rightAnchor.constraint(equalTo: busyIndicator.leftAnchor)
            ])
        self.accessoryType = .disclosureIndicator

        statusSwitch.addTarget(self, action: #selector(switchToggled), for: .valueChanged)
    }

    @objc func switchToggled() {
        onSwitchToggled?(statusSwitch.isOn)
    }

    private func update(from status: TunnelStatus?) {
        guard let status = status else {
            reset()
            return
        }
        DispatchQueue.main.async { [weak statusSwitch, weak busyIndicator] in
            guard let statusSwitch = statusSwitch, let busyIndicator = busyIndicator else { return }
            statusSwitch.isOn = !(status == .deactivating || status == .inactive)
            statusSwitch.isUserInteractionEnabled = (status == .inactive || status == .active)
            if (status == .inactive || status == .active) {
                busyIndicator.stopAnimating()
            } else {
                busyIndicator.startAnimating()
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func reset() {
        statusSwitch.isOn = false
        statusSwitch.isUserInteractionEnabled = false
        busyIndicator.stopAnimating()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        reset()
    }
}

class BorderedTextButton: UIView {
    let button: UIButton

    override var intrinsicContentSize: CGSize {
        let buttonSize = button.intrinsicContentSize
        return CGSize(width: buttonSize.width + 32, height: buttonSize.height + 16)
    }

    var title: String {
        get { return button.title(for: .normal) ?? "" }
        set(value) { button.setTitle(value, for: .normal) }
    }

    var onTapped: (() -> Void)?

    init() {
        button = UIButton(type: .system)
        super.init(frame: CGRect.zero)
        addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: self.centerYAnchor)
            ])
        layer.borderWidth = 1
        layer.cornerRadius = 5
        layer.borderColor = button.tintColor.cgColor
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
    }

    @objc func buttonTapped() {
        onTapped?()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
