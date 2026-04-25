//
//  AddGroupView.swift
//  WeItems
//

import SwiftUI

struct AddGroupView: View {
    @Environment(\.dismiss) private var dismiss
    var groupStore: GroupStore
    var editingGroup: ItemGroup? = nil
    var onDeleteGroup: ((ItemGroup) -> Void)? = nil

    @State private var name = ""
    @State private var selectedIcon = "folder"
    @State private var selectedColor: GroupColor = .blue
    @State private var showDeleteConfirm = false

    private let icons = [
        "folder", "tray", "archivebox", "briefcase", "bag",
        "cart", "gift", "heart", "star", "house",
        "car", "airplane", "macbook", "iphone", "applewatch",
        "camera", "headphones", "gamecontroller", "book", "graduationcap"
    ]

    private var isValid: Bool {
        !name.isEmpty
    }

    private var iconSection: some View {
        Section("图标") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 16) {
                ForEach(icons, id: \.self) { icon in
                    iconButton(for: icon)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func iconButton(for icon: String) -> some View {
        let isSelected = selectedIcon == icon
        let bgColor = isSelected ? selectedColor.swiftUIColor : Color.gray.opacity(0.2)
        let fgColor: Color = isSelected ? .white : .primary

        return Image(systemName: icon)
            .font(.title2)
            .frame(width: 50, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(bgColor)
            )
            .foregroundStyle(fgColor)
            .onTapGesture {
                selectedIcon = icon
            }
    }

    private var colorSection: some View {
        Section("颜色") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(GroupColor.allCases, id: \.self) { color in
                        colorButton(for: color)
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowInsets(EdgeInsets())
        }
    }

    private func colorButton(for color: GroupColor) -> some View {
        let isSelected = selectedColor == color
        let strokeWidth: CGFloat = isSelected ? 3 : 0
        let outerStrokeWidth: CGFloat = isSelected ? 1 : 0

        return Circle()
            .fill(color.swiftUIColor)
            .frame(width: 40, height: 40)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: strokeWidth)
            )
            .overlay(
                Circle()
                    .stroke(color.swiftUIColor, lineWidth: outerStrokeWidth)
            )
            .onTapGesture {
                selectedColor = color
            }
    }

    private var previewSection: some View {
        Section("预览") {
            HStack {
                Image(systemName: selectedIcon)
                    .font(.title2)
                    .foregroundStyle(selectedColor.swiftUIColor)
                    .frame(width: 40, height: 40)
                    .background(selectedColor.swiftUIColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(name.isEmpty ? "分组名称" : name)
                    .font(.headline)

                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("分组信息") {
                    TextField("分组名称", text: $name)
                }

                iconSection
                colorSection
                if editingGroup == nil {
                    previewSection
                }
                
                if editingGroup != nil {
                    Section {
                        Button("删除分组", role: .destructive) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle(editingGroup != nil ? "编辑分组" : "新建分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editingGroup != nil ? "保存" : "创建") {
                        if let editingGroup = editingGroup {
                            saveGroup(editingGroup)
                        } else {
                            createGroup()
                        }
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let group = editingGroup {
                    name = group.name
                    selectedIcon = group.icon
                    selectedColor = group.color
                }
            }
        }
        .presentationDetents([.medium])
        .alert("删除分组", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let group = editingGroup {
                    onDeleteGroup?(group)
                    dismiss()
                }
            }
        } message: {
            Text("删除分组后，该分组下的物品将变为无分组状态。确定要删除吗？")
        }
    }

    private func createGroup() {
        let newGroup = ItemGroup(
            name: name,
            icon: selectedIcon,
            color: selectedColor
        )
        groupStore.add(newGroup)
        dismiss()
    }
    
    private func saveGroup(_ group: ItemGroup) {
        var updated = group
        updated.name = name
        updated.icon = selectedIcon
        updated.color = selectedColor
        groupStore.update(updated)
        dismiss()
    }
}

#Preview {
    AddGroupView(groupStore: GroupStore())
}
