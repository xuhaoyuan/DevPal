import SwiftUI

/// Manage git includeIf conditional configs (per-directory user/email)
struct GitIdentityView: View {
    @ObservedObject var viewModel: SSHViewModel
    @State private var includes: [GitConfigManager.ConditionalInclude] = []
    @State private var globalUser: GitConfigManager.GitUserInfo?
    @State private var isLoading = true
    @State private var showAddSheet = false

    // Add form
    @State private var newGitdir = "~/work/"
    @State private var newName = ""
    @State private var newEmail = ""

    private let gitConfigManager = GitConfigManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Git 身份管理")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("添加目录规则", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)

            Divider()

            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Global user info
                        if let user = globalUser {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("全局 Git 身份 (~/.gitconfig)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                HStack(spacing: 16) {
                                    Label(user.name, systemImage: "person.fill")
                                        .font(.system(size: 12))
                                    Label(user.email, systemImage: "envelope.fill")
                                        .font(.system(size: 12))
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                        }

                        // Explanation
                        VStack(alignment: .leading, spacing: 4) {
                            Label("按目录自动切换身份", systemImage: "info.circle")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                            Text("通过 git 的 includeIf 机制，不同目录下的仓库自动使用不同的 user.name 和 user.email。比如 ~/work/ 下用公司邮箱，~/personal/ 下用个人邮箱。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.05)))

                        // Conditional includes
                        if includes.isEmpty {
                            Text("暂无目录条件配置")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            Text("目录条件规则 (includeIf)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            ForEach(includes) { include in
                                includeRow(include)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            addIncludeSheet
        }
        .task {
            await loadData()
        }
    }

    private func includeRow(_ include: GitConfigManager.ConditionalInclude) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    Text(include.gitdir)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("→ \(include.path)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var addIncludeSheet: some View {
        VStack(spacing: 16) {
            Text("添加目录条件配置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("目录路径").font(.system(size: 12, weight: .medium))
                TextField("~/work/", text: $newGitdir)
                    .textFieldStyle(.roundedBorder)
                Text("该目录下所有 git 仓库将使用以下身份")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("用户名").font(.system(size: 12, weight: .medium))
                TextField("Your Name", text: $newName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("邮箱").font(.system(size: 12, weight: .medium))
                TextField("your@company.com", text: $newEmail)
                    .textFieldStyle(.roundedBorder)
            }

            // Preview
            VStack(alignment: .leading, spacing: 4) {
                Text("将在 ~/.gitconfig 添加：").font(.system(size: 11, weight: .medium))
                Text("[includeIf \"gitdir:\(newGitdir)\"]\n    path = ~/.gitconfig-\(sanitizedLabel)")
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            }

            HStack {
                Button("取消") { showAddSheet = false }
                Spacer()
                Button("添加") {
                    Task {
                        await addInclude()
                        showAddSheet = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newGitdir.isEmpty || (newName.isEmpty && newEmail.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var sanitizedLabel: String {
        newGitdir
            .replacingOccurrences(of: "~/", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        globalUser = await gitConfigManager.loadGlobalUser()
        includes = await gitConfigManager.loadConditionalIncludes()
    }

    private func addInclude() async {
        let configPath = "~/.gitconfig-\(sanitizedLabel)"
        do {
            try await gitConfigManager.addConditionalInclude(
                gitdir: newGitdir,
                configPath: configPath,
                userName: newName.isEmpty ? nil : newName,
                userEmail: newEmail.isEmpty ? nil : newEmail
            )
            viewModel.successMessage = "目录条件配置已添加"
            await loadData()
            newGitdir = "~/work/"
            newName = ""
            newEmail = ""
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}
