//
//  EditItemView.swift
//  WeItems
//

import SwiftUI
import PhotosUI

struct EditItemView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ItemStore
    @ObservedObject var groupStore: GroupStore
    
    @State var item: Item
    @State private var selectedType: ItemType
    @State private var showingAddGroup = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var ownedDate: Date
    
    init(item: Item, store: ItemStore, groupStore: GroupStore) {
        self._item = State(initialValue: item)
        self.store = store
        self.groupStore = groupStore
        self._selectedType = State(initialValue: ItemType(rawValue: item.type) ?? .other)
        self._ownedDate = State(initialValue: item.ownedDate ?? item.createdAt)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 基本信息
                Section {
                    TextField("物品名称", text: $item.name)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .submitLabel(.done)
                        .listRowSeparator(.hidden)
                    
                    if !item.isPriceless {
                        HStack {
                            Text("¥")
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            TextField("价格", value: $item.price, format: .number)
                                .keyboardType(.decimalPad)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.semibold)
                        }
                        .listRowSeparator(.hidden)
                    }
                    
                    Picker(selection: $selectedType) {
                        ForEach(ItemType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    } label: {
                        Text("类型")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .listRowSeparator(.hidden)
                    .onChange(of: selectedType) { _, newValue in
                        item.type = newValue.rawValue
                    }
                    
                    Toggle(isOn: $item.isLargeItem) {
                        Text("大件")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .listRowSeparator(.hidden)
                    
                    Toggle(isOn: $item.isPriceless) {
                        Text("无价之物")
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.semibold)
                    }
                    .listRowSeparator(.hidden)
                    
                    DatePicker(selection: $ownedDate, displayedComponents: .date) {
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
                                item.groupId = nil
                            } label: {
                                Text("全部")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(item.groupId == nil ? .bold : .regular)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(item.groupId == nil ? Color.blue.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
                                    )
                                    .foregroundStyle(item.groupId == nil ? .blue : .primary)
                                    .overlay(
                                        Capsule()
                                            .stroke(item.groupId == nil ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            ForEach(groupStore.groups) { group in
                                Button {
                                    item.groupId = group.id
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: group.icon)
                                            .font(.caption)
                                        Text(group.name)
                                            .font(.system(.subheadline, design: .rounded))
                                            .fontWeight(item.groupId == group.id ? .bold : .regular)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(item.groupId == group.id ? group.color.swiftUIColor.opacity(0.15) : Color(.tertiarySystemGroupedBackground))
                                    )
                                    .foregroundStyle(item.groupId == group.id ? group.color.swiftUIColor : .primary)
                                    .overlay(
                                        Capsule()
                                            .stroke(item.groupId == group.id ? group.color.swiftUIColor.opacity(0.3) : Color.clear, lineWidth: 1)
                                    )
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
                    .listRowSeparator(.hidden)
                } header: {
                    Text("所属分组")
                        .font(.system(.footnote, design: .rounded))
                        .fontWeight(.semibold)
                }
                
                // 图片选择
                Section("图片") {
                    VStack(spacing: 12) {
                        if let imageData = item.imageData,
                           let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 200)
                                    .overlay(
                                        VStack(spacing: 8) {
                                            Image(systemName: "photo.badge.plus")
                                                .font(.system(size: 40))
                                                .foregroundStyle(.gray)
                                            Text("选择图片")
                                                .foregroundStyle(.secondary)
                                        }
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if item.imageData != nil {
                            HStack {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    Label("更换照片", systemImage: "photo")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                
                                Divider()
                                Button(role: .destructive) {
                                    item.imageData = nil
                                    item.compressedImageData = nil
                                    item.imageChanged = true
                                    selectedPhoto = nil
                                } label: {
                                    Label("删除图片", systemImage: "trash")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                    .onChange(of: selectedPhoto) { _, newValue in
                        Task {
                            if let data = try? await newValue?.loadTransferable(type: Data.self) {
                                item.imageData = data
                                item.imageChanged = true
                                if let uiImage = UIImage(data: data) {
                                    item.compressedImageData = uiImage.jpegData(compressionQuality: 0.7)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // 详情
                Section("详情描述") {
                    TextEditor(text: $item.details)
                        .frame(minHeight: 80)
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
        }
    }
    
    private func saveItem() {
        item.ownedDate = ownedDate
        store.update(item)
        dismiss()
    }
}

#Preview {
    EditItemView(
        item: Item(name: "测试物品", details: "详情", purchaseLink: "", price: 100, type: "其他"),
        store: ItemStore(),
        groupStore: GroupStore()
    )
}
