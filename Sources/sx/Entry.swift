import SxCommand

@main
struct Entry {
    static func main() async {
        // Delegate to SxCommand's entry point so all exit-code / diagnostic
        // policy (including ArgumentParser parse-failure mapping) lives in one
        // tested place rather than in this wrapper.
        await Sx.runAsMain()
    }
}
