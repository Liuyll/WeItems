//
//  EditItemView.swift
//  WeItems
//

import SwiftUI
import Combine
import PhotosUI

/// 编辑物品的 Draft（防止嵌套 sheet 切后台数据丢失）
class ItemDraft: ObservableObject {
    @Published var name: String
    @Published var details: String
    @Published var purchaseLink: String
    @Published var imageData: Data?
    @Published var compressedImageData: Data?
    @Published var imageChanged: Bool
    @Published var price: Double
    @Published var type: String
    @Published var groupId: UUID?
    @Published var isLargeItem: Bool
    @Published var isPriceless: Bool
    @Published var ownedDate: Date
    @Published var selectedType: ItemType
    
    init(item: Item) {
        self.name = item.name
        self.details = item.details
        self.purchaseLink = item.purchaseLink
        self.imageData = item.imageData
        self.compressedImageData = item.compressedImageData
        self.imageChanged = item.imageChanged
        self.price = item.price
        self.type = item.type
        self.groupId = item.groupId
        self.isLargeItem = item.isLargeItem
        self.isPriceless = item.isPriceless
        self.ownedDate = item.ownedDate ?? item.createdAt
        self.selectedType = ItemType(rawValue: item.type) ?? .other
    }
    
    func applyChanges(to item: Item) -> Item {
        var updated = item
        updated.name = name
        updated.details = details
        updated.purchaseLink = purchaseLink
        updated.imageData = imageData
        updated.compressedImageData = compressedImageData
        updated.imageChanged = imageChanged
        updated.price = price
        updated.type = type
        updated.groupId = groupId
        updated.isLargeItem = isLargeItem
        updated.isPriceless = isPriceless
        updated.ownedDate = ownedDate
        return updated
    }
}

struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    var store: ItemStore
    var groupStore: GroupStore
    
    let originalItem: Item
    @ObservedObject var draft: ItemDraft
    @State private var showingAddGroup = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showDeleteConfirm = false
    @State private var fullScreenImage: UIImage? = nil
    
    init(draft: ItemDraft, item: Item, store: ItemStore, groupStore: GroupStore) {
        self.draft = draft
        self.originalItem = item
        self.store = store
        self.groupStore = groupStore
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 基本信息
                Section {
                    TextField("物品名称", text: $draft.name)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .submitLabel(.done)
                        .listRowSeparator(.hidden)
                    
                    if !draft.isPriceless {
                        HStack {
                            Text("¥")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            TextField("价格", value: $draft.price, format: .number)
                                .keyboardType(.decimalPad)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                        }
                        .listRowSeparator(.hidden)
                    }
                    
                    Picker(selection: $draft.selectedType) {
                        ForEach(ItemType.allCases, id: \.self) { type in
                            HStack(spacing: 6) {
                                type.iconImage(size: 16)
                                Text(type.rawValue)
                            }
                                .tag(type)
                        }
                    } label: {
                        Text("类型")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .listRowSeparator(.hidden)
                    .onChange(of: draft.selectedType) { _, newValue in
                        draft.type = newValue.rawValue
                    }
                    
                    Toggle(isOn: $draft.isLargeItem) {
                        Text("大件")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .listRowSeparator(.hidden)
                    
                    Toggle(isOn: $draft.isPriceless) {
                        Text("无价之物")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .listRowSeparator(.hidden)
                    
                    DatePicker(selection: $draft.ownedDate, displayedComponents: .date) {
                        Text("拥有日期")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .listRowSeparator(.hidden)
                } header: {
                    Text("基本信息")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.semibold)
                }
                
                // 分组选择
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // 无分组
                            Button {
                                draft.groupId = nil
                            } label: {
                                Text("全部")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(draft.groupId == nil ? .bold : .regular)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(draft.groupId == nil ? Color.blue.opacity(0.15) : Color(.systemGray5))
                                    )
                                    .foregroundStyle(draft.groupId == nil ? .blue : .primary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            ForEach(groupStore.groups) { group in
                                Button {
                                    draft.groupId = group.id
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: group.icon)
                                            .font(.caption)
                                        Text(group.name)
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(draft.groupId == group.id ? .bold : .regular)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(draft.groupId == group.id ? group.color.swiftUIColor.opacity(0.15) : Color(.systemGray5))
                                    )
                                    .foregroundStyle(draft.groupId == group.id ? group.color.swiftUIColor : .primary)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            // 新增分组
                            Button {
                                showingAddGroup = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.caption)
                                    Text("新增")
                                        .font(.system(.subheadline, design: .rounded))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                                )
                                .foregroundStyle(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 2)
                    .listRowSeparator(.hidden)
                } header: {
                    Text("所属分组")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.semibold)
                }
                
                // 图片选择
                Section {
                    if let imageData = draft.imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .onTapGesture { fullScreenImage = uiImage }
                        
                        HStack(spacing: 0) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("更换")
                                        .font(.system(.subheadline, design: .rounded))
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .frame(height: 20)
                            
                            Button {
                                draft.imageData = nil
                                draft.compressedImageData = nil
                                draft.imageChanged = true
                                selectedPhoto = nil
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("删除")
                                        .font(.system(.subheadline, design: .rounded))
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowSeparator(.hidden)
                    } else {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            RoundedRectangle(cornerRadius: 0)
                                .fill(Color.blue)
                                .frame(height: 200)
                                .overlay(
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.white)
                                )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    }
                    
                    EmptyView()
                        .onChange(of: selectedPhoto) { _, newValue in
                            Task {
                                if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                    draft.imageData = data
                                    draft.imageChanged = true
                                    if let uiImage = UIImage(data: data) {
                                        draft.compressedImageData = uiImage.jpegData(compressionQuality: 0.7)
                                    }
                                }
                            }
                        }
                        .frame(height: 0)
                } header: {
                    Text("照片")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.semibold)
                }
                
                // 详情
                Section {
                    TextEditor(text: $draft.details)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(minHeight: 80)
                } header: {
                    Text("详情描述")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.semibold)
                }
                
                // 删除物品
                Section {
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("删除物品")
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.red)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                
            }
            .navigationTitle("编辑物品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveItem()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingAddGroup) {
                AddGroupView(groupStore: groupStore)
            }
            .customBlueConfirmAlert(
                isPresented: $showDeleteConfirm,
                message: "删除后无法恢复，确定要删除「\(draft.name)」吗？",
                confirmText: "删除",
                cancelText: "取消",
                confirmColor: .blue,
                cancelColor: .green,
                backgroundColor: .yellow,
                width: 260,
                onConfirm: {
                    store.delete(originalItem)
                    dismiss()
                }
            )
            .fullScreenImageViewer(uiImage: $fullScreenImage)
        }
    }
    
    private func saveItem() {
        let updated = draft.applyChanges(to: originalItem)
        store.update(updated)
        dismiss()
    }
}

#Preview {
    let testItem = Item(name: "测试物品", details: "详情", purchaseLink: "", price: 100, type: "其他")
    EditItemView(
        draft: ItemDraft(item: testItem),
        item: testItem,
        store: ItemStore(),
        groupStore: GroupStore()
    )
}
