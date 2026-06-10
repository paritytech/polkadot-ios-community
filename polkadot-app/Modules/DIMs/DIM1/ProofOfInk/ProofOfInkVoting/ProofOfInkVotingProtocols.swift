import PolkadotUI
import UIKitExt

protocol ProofOfInkVotingViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: ProofOfInkVotingViewModel)
}

protocol ProofOfInkVotingPresenterProtocol: AnyObject {
    func setup()
    func close()
    func report()
    func vote(result: ProofOfInkVotingLayout.VoteResult)
}

protocol ProofOfInkVotingInteractorInputProtocol: AnyObject {
    func setup()
}

protocol ProofOfInkVotingInteractorOutputProtocol: AnyObject {}

protocol ProofOfInkVotingWireframeProtocol: AnyObject {
    func close(view: ProofOfInkVotingViewProtocol?)
    func showReport(from view: ProofOfInkVotingViewProtocol?)
}
