import Foundation
import SubstrateSdk

protocol URLScanDelegate: AnyObject {
    func urlScanDidReceiveResult(_ url: URL)
}
